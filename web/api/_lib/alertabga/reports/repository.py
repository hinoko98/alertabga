"""Acceso a datos de reportes ciudadanos en MongoDB (ADR 0003). La API autoriza antes de llamar aquí.

Lo que antes hacían los triggers de Postgres vive aquí y en `ReportService`:
radicado atómico, historial `CREADO`, timeline público sin notas internas.
Categorías y ajustes vienen de Supabase (los administra el panel web)."""

import uuid
from datetime import UTC, datetime
from typing import Any, Protocol

from pymongo import ReturnDocument

from ..mongo_store import hit_rate_limit, write_audit

PUBLIC_ACTIONS = ("CREADO", "CAMBIO_ESTADO", "CIERRE", "MENSAJE_CIUDADANO")
DEFAULT_RATE = {"max": 5, "window_minutes": 60}


class ReportRepository(Protocol):
    def active_category(self, category_id: str) -> dict | None: ...
    def active_categories(self) -> list[dict]: ...
    def rate_limit_setting(self) -> dict: ...
    def territorial_scope(self) -> dict | None: ...
    def hit_rate_limit(self, key: str, max_hits: int, window_minutes: int) -> bool: ...
    def insert_incident(self, row: dict[str, Any]) -> dict: ...
    def find_by_radicado(self, radicado: str) -> dict | None: ...
    def public_timeline(self, incident_id: str) -> list[dict]: ...
    def list_mine(self, user_id: str) -> list[dict]: ...
    def count_evidence(self, incident_id: str, statuses: tuple[str, ...]) -> int: ...
    def insert_evidence(self, row: dict[str, Any]) -> dict: ...
    def find_evidence(self, evidence_id: str, incident_id: str) -> dict | None: ...
    def update_evidence(self, evidence_id: str, values: dict[str, Any]) -> None: ...
    def audit(self, action: str, entity: str, entity_id: str | None, actor_id: str | None,
              actor_role: str | None, metadata: dict | None = None, ip_hash: str | None = None) -> None: ...


class ConfigSource(Protocol):
    def categories(self) -> list[dict]: ...
    def setting(self, key: str) -> dict | None: ...


class SupabaseConfig:
    """Catálogo y ajustes institucionales (Postgres, gestionados desde el panel)."""

    def categories(self) -> list[dict]:
        from ..supabase_client import service_client

        res = (service_client().table("categories").select("id, name, description, icon, color")
               .eq("active", True).order("name").execute())
        return res.data or []

    def setting(self, key: str) -> dict | None:
        from ..supabase_client import service_client

        res = service_client().table("app_settings").select("value").eq("key", key).limit(1).execute()
        return res.data[0]["value"] if res.data else None


def _iso(v: Any) -> Any:
    if isinstance(v, datetime):
        return (v if v.tzinfo else v.replace(tzinfo=UTC)).isoformat()
    return v


def _now() -> datetime:
    return datetime.now(UTC)


class MongoReportRepository:
    def __init__(self, db: Any, config: ConfigSource) -> None:
        self.db = db
        self.config = config

    # ------------------------------------------------------------ configuración
    def active_category(self, category_id: str) -> dict | None:
        return next(({"id": c["id"], "name": c["name"]} for c in self.config.categories() if c["id"] == category_id),
                    None)

    def active_categories(self) -> list[dict]:
        return self.config.categories()

    def rate_limit_setting(self) -> dict:
        return self.config.setting("rate_limit_reports") or DEFAULT_RATE

    def territorial_scope(self) -> dict | None:
        return self.config.setting("territorial_scope")

    def hit_rate_limit(self, key: str, max_hits: int, window_minutes: int) -> bool:
        return hit_rate_limit(self.db, key, max_hits, window_minutes)

    # ------------------------------------------------------------ incidentes
    def _next_radicado(self, now: datetime) -> str:
        year = _bogota_year(now)
        doc = self.db.counters.find_one_and_update(
            {"_id": f"radicado-{year}"}, {"$inc": {"seq": 1}}, upsert=True, return_document=ReturnDocument.AFTER)
        return f"BGA-{year}-{int(doc['seq']):06d}"

    def insert_incident(self, row: dict[str, Any]) -> dict:
        now = _now()
        doc = {
            "_id": str(uuid.uuid4()),
            "radicado": self._next_radicado(now),
            "category_id": row["category_id"],
            "category_name": row["category_name"],
            "description": row["description"],
            "additional_info": row.get("additional_info"),
            "occurred_at": datetime.fromisoformat(row["occurred_at"]),
            "received_at": now,
            "location": {"type": "Point", "coordinates": [row["lon"], row["lat"]]},
            "accuracy_m": row.get("accuracy_m"),
            "location_manual": bool(row.get("location_manual")),
            "address_text": row.get("address_text"),
            "status": "RECIBIDO",
            "priority": "MEDIA",
            "verification_level": "REPORTE_CIUDADANO",
            "source": row["source"],
            "reporter_id": row.get("reporter_id"),
            "anon_token_hash": row.get("anon_token_hash"),
            "quadrant_id": None,  # sin polígonos oficiales: asignación manual desde el panel
            "assigned_to": None,
            "out_of_scope": bool(row.get("out_of_scope")),
            "updated_at": now,
        }
        self.db.incidents.insert_one(doc)
        self.db.incident_history.insert_one({
            "incident_id": doc["_id"], "actor_id": doc["reporter_id"], "action": "CREADO", "old_status": None,
            "new_status": "RECIBIDO", "note": "Reporte recibido", "is_internal": False,
            "metadata": {"out_of_scope": doc["out_of_scope"]}, "created_at": now, "seq": 0,
        })
        return {"id": doc["_id"], "radicado": doc["radicado"], "received_at": _iso(now), "status": "RECIBIDO",
                "out_of_scope": doc["out_of_scope"]}

    def find_by_radicado(self, radicado: str) -> dict | None:
        d = self.db.incidents.find_one({"radicado": radicado})
        if not d:
            return None
        return {"id": d["_id"], "radicado": d["radicado"], "status": d["status"], "description": d["description"],
                "occurred_at": _iso(d["occurred_at"]), "received_at": _iso(d["received_at"]),
                "address_text": d.get("address_text"), "out_of_scope": d.get("out_of_scope", False),
                "source": d["source"], "reporter_id": d.get("reporter_id"),
                "anon_token_hash": d.get("anon_token_hash"), "category": d.get("category_name", "")}

    def public_timeline(self, incident_id: str) -> list[dict]:
        cur = (self.db.incident_history
               .find({"incident_id": incident_id, "is_internal": False, "action": {"$in": list(PUBLIC_ACTIONS)}},
                     {"_id": 0, "action": 1, "new_status": 1, "note": 1, "created_at": 1})
               .sort([("created_at", 1), ("seq", 1)]))
        return [{**h, "created_at": _iso(h["created_at"])} for h in cur]

    def list_mine(self, user_id: str) -> list[dict]:
        cur = (self.db.incidents.find({"reporter_id": user_id},
                                      {"radicado": 1, "status": 1, "received_at": 1, "category_name": 1})
               .sort("received_at", -1).limit(100))
        return [{"radicado": d["radicado"], "status": d["status"], "received_at": _iso(d["received_at"]),
                 "category": d.get("category_name", "")} for d in cur]

    # ------------------------------------------------------------ evidencias
    def count_evidence(self, incident_id: str, statuses: tuple[str, ...]) -> int:
        return self.db.evidence.count_documents({"incident_id": incident_id, "status": {"$in": list(statuses)}})

    def insert_evidence(self, row: dict[str, Any]) -> dict:
        doc = {"_id": row["id"], **{k: v for k, v in row.items() if k != "id"}, "status": "PENDIENTE",
               "created_at": _now(), "confirmed_at": None}
        self.db.evidence.insert_one(doc)
        return {**row, "status": "PENDIENTE"}

    def find_evidence(self, evidence_id: str, incident_id: str) -> dict | None:
        d = self.db.evidence.find_one({"_id": evidence_id, "incident_id": incident_id})
        if not d:
            return None
        return {"id": d["_id"], "incident_id": d["incident_id"], "storage_key": d["storage_key"],
                "mime_type": d["mime_type"], "size_bytes": d["size_bytes"], "status": d["status"]}

    def update_evidence(self, evidence_id: str, values: dict[str, Any]) -> None:
        v = dict(values)
        if isinstance(v.get("confirmed_at"), str):
            v["confirmed_at"] = datetime.fromisoformat(v["confirmed_at"])
        self.db.evidence.update_one({"_id": evidence_id}, {"$set": v})

    def audit(self, action: str, entity: str, entity_id: str | None, actor_id: str | None,
              actor_role: str | None, metadata: dict | None = None, ip_hash: str | None = None) -> None:
        write_audit(self.db, action, entity, entity_id, actor_id, actor_role, metadata, ip_hash)


def _bogota_year(now: datetime) -> int:
    from zoneinfo import ZoneInfo

    try:
        return now.astimezone(ZoneInfo("America/Bogota")).year
    except Exception:  # sin base tz (Windows sin tzdata): Bogotá es UTC−5 fijo
        from datetime import timedelta

        return (now - timedelta(hours=5)).year
