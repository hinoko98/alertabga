"""Gestión institucional de incidentes sobre MongoDB (Fase 3).

La API autoriza por rol antes de llegar aquí; este servicio aplica las reglas finas de `workflow`
(quién gestiona qué incidente, transiciones válidas, mensajes obligatorios) y escribe historial y auditoría.
"""

import csv
import io
import re
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta, timezone
from statistics import median
from typing import Any, Protocol

from ..mongo_store import write_audit
from . import workflow as wf

BOGOTA = timezone(timedelta(hours=-5))  # Colombia no tiene horario de verano
WEEKDAYS = ("Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo")
MAX_PAGE = 100
MAX_MAP_POINTS = 5000


class NotFound(Exception):
    pass


class Forbidden(Exception):
    pass


class Conflict(Exception):
    pass


class InvalidData(Exception):
    pass


class StaffDirectory(Protocol):
    def staff(self) -> list[dict]: ...
    def get(self, staff_id: str) -> dict | None: ...


class EvidenceUrls(Protocol):
    def presign_get(self, key: str, ttl: int = 300, host: str | None = None) -> str: ...


@dataclass(frozen=True)
class Actor:
    id: str
    role: str
    full_name: str | None = None


@dataclass
class Filters:
    statuses: list[str] | None = None
    category_id: str | None = None
    priority: str | None = None
    assigned: str | None = None  # "me", "none" o id de funcionario
    q: str | None = None
    date_from: date | None = None
    date_to: date | None = None
    days: int | None = None


def _utc(v: datetime | None) -> datetime | None:
    if v is None:
        return None
    return v if v.tzinfo else v.replace(tzinfo=UTC)


def _iso(v: Any) -> Any:
    return _utc(v).isoformat() if isinstance(v, datetime) else v


def _local_day(v: datetime) -> date:
    return _utc(v).astimezone(BOGOTA).date()  # type: ignore[union-attr]


def _now() -> datetime:
    return datetime.now(UTC)


class PanelService:
    def __init__(self, db: Any, directory: StaffDirectory, storage: EvidenceUrls) -> None:
        self.db = db
        self.directory = directory
        self.storage = storage

    # ================================================================== consultas
    def _query(self, f: Filters, actor: Actor) -> dict:
        q: dict[str, Any] = {}
        if f.statuses:
            q["status"] = {"$in": f.statuses}
        if f.category_id:
            q["category_id"] = f.category_id
        if f.priority:
            q["priority"] = f.priority
        if f.assigned == "me":
            q["assigned_to"] = actor.id
        elif f.assigned == "none":
            q["assigned_to"] = None
        elif f.assigned:
            q["assigned_to"] = f.assigned
        received: dict[str, datetime] = {}
        if f.days:
            received["$gte"] = _now() - timedelta(days=f.days)
        if f.date_from:
            received["$gte"] = datetime.combine(f.date_from, datetime.min.time(), BOGOTA).astimezone(UTC)
        if f.date_to:
            received["$lt"] = datetime.combine(f.date_to + timedelta(days=1), datetime.min.time(), BOGOTA).astimezone(UTC)
        if received:
            q["received_at"] = received
        if f.q and f.q.strip():
            text = re.escape(f.q.strip()[:80])  # el texto del usuario nunca se interpreta como regex
            q["$or"] = [{"radicado": {"$regex": text, "$options": "i"}},
                        {"description": {"$regex": text, "$options": "i"}},
                        {"address_text": {"$regex": text, "$options": "i"}}]
        return q

    @staticmethod
    def _row(d: dict) -> dict:
        lon, lat = d["location"]["coordinates"]
        return {
            "radicado": d["radicado"], "category": d.get("category_name", ""), "category_id": d.get("category_id"),
            "status": d["status"], "priority": d.get("priority", "MEDIA"), "source": d.get("source"),
            "received_at": _iso(d["received_at"]), "occurred_at": _iso(d.get("occurred_at")),
            "address_text": d.get("address_text"), "lat": lat, "lon": lon,
            "assigned_to": d.get("assigned_to"), "assigned_name": d.get("assigned_name"),
            "out_of_scope": bool(d.get("out_of_scope")), "demo": bool(d.get("demo")),
        }

    def list_incidents(self, f: Filters, actor: Actor, page: int = 1, page_size: int = 25) -> dict:
        page_size = max(1, min(page_size, MAX_PAGE))
        page = max(1, page)
        q = self._query(f, actor)
        total = self.db.incidents.count_documents(q)
        cur = (self.db.incidents.find(q).sort([("received_at", -1), ("radicado", -1)])
               .skip((page - 1) * page_size).limit(page_size))
        return {"items": [self._row(d) for d in cur], "total": total, "page": page, "page_size": page_size}

    def _incident(self, radicado: str) -> dict:
        d = self.db.incidents.find_one({"radicado": radicado})
        if not d:
            raise NotFound()
        return d

    def _actor_name(self, actor_id: str | None, incident: dict) -> str:
        if actor_id is None:
            return "Ciudadano anónimo" if not incident.get("reporter_id") else "Sistema"
        if actor_id == incident.get("reporter_id"):
            return "Ciudadano"
        s = self.directory.get(actor_id)
        return (s or {}).get("full_name") or "Funcionario"

    def _reporter(self, d: dict) -> dict:
        if not d.get("reporter_id"):
            return {"type": "ANONIMO"}
        c = self.db.citizens.find_one({"_id": d["reporter_id"]}, {"full_name": 1, "email": 1, "phone": 1}) or {}
        return {"type": "CUENTA", "full_name": c.get("full_name"), "email": c.get("email"), "phone": c.get("phone")}

    def _permissions(self, d: dict, actor: Actor) -> dict:
        return {
            "transitions": wf.allowed_transitions(actor.role, actor.id, d),
            "can_take": wf.can_take(actor.role, d),
            "can_assign": wf.is_manager(actor.role),
            "can_manage": wf.can_manage(actor.role, actor.id, d),
        }

    def detail(self, radicado: str, actor: Actor, host: str | None = None) -> dict:
        d = self._incident(radicado)
        history = [
            {"at": _iso(h["created_at"]), "action": h["action"], "old_status": h.get("old_status"),
             "new_status": h.get("new_status"), "note": h.get("note"), "internal": bool(h.get("is_internal")),
             "actor": self._actor_name(h.get("actor_id"), d)}
            for h in self.db.incident_history.find({"incident_id": d["_id"]}).sort([("created_at", 1), ("seq", 1)])
        ]
        evidence = []
        for e in self.db.evidence.find({"incident_id": d["_id"], "status": "CONFIRMADA"}).sort("created_at", 1):
            try:
                url = self.storage.presign_get(e["storage_key"], host=host)
            except Exception:  # almacenamiento no configurado: se muestra la ficha sin imagen
                url = None
            evidence.append({"id": e["_id"], "mime_type": e["mime_type"], "size_bytes": e["size_bytes"], "url": url})
        self._audit("VER_INCIDENTE", d, actor)
        return {
            **self._row(d), "id": d["_id"], "description": d["description"],
            "additional_info": d.get("additional_info"), "accuracy_m": d.get("accuracy_m"),
            "location_manual": bool(d.get("location_manual")), "verification_level": d.get("verification_level"),
            "first_response_at": _iso(d.get("first_response_at")), "closed_at": _iso(d.get("closed_at")),
            "reporter": self._reporter(d), "evidence": evidence, "history": history,
            "permissions": self._permissions(d, actor),
        }

    # ================================================================== acciones
    def _history(self, d: dict, actor: Actor, action: str, *, note: str | None, internal: bool,
                 old: str | None = None, new: str | None = None, metadata: dict | None = None,
                 at: datetime | None = None) -> None:
        seq = self.db.incident_history.count_documents({"incident_id": d["_id"]})
        self.db.incident_history.insert_one({
            "incident_id": d["_id"], "actor_id": actor.id, "action": action, "old_status": old, "new_status": new,
            "note": note, "is_internal": internal, "metadata": metadata or {}, "created_at": at or _now(), "seq": seq,
        })

    def _audit(self, action: str, d: dict | None, actor: Actor, metadata: dict | None = None) -> None:
        write_audit(self.db, action, "incident", d["_id"] if d else None, actor.id, actor.role, metadata)

    def _set(self, d: dict, values: dict) -> None:
        values = {**values, "updated_at": _now()}
        if d["status"] in ("RECIBIDO",) and not d.get("first_response_at") and values.get("status"):
            values["first_response_at"] = values["updated_at"]
        self.db.incidents.update_one({"_id": d["_id"]}, {"$set": values})

    def _require_manage(self, d: dict, actor: Actor) -> None:
        if not wf.can_manage(actor.role, actor.id, d):
            raise Forbidden()

    def change_status(self, radicado: str, actor: Actor, new: str, public_message: str | None = None,
                      internal_note: str | None = None) -> dict:
        d = self._incident(radicado)
        old = d["status"]
        if new not in wf.STATUSES:
            raise InvalidData("Estado no válido")
        if new not in wf.TRANSITIONS.get(old, ()):
            raise Conflict(f"No se puede pasar de {old} a {new}")
        if new not in wf.allowed_transitions(actor.role, actor.id, d):
            raise Forbidden()
        message = (public_message or "").strip() or None
        if wf.needs_message(old, new) and not message:
            raise InvalidData("Escriba un mensaje para el ciudadano explicando la decisión")
        if new == "ASIGNADO" and not d.get("assigned_to"):
            raise InvalidData("Asigne un funcionario antes de marcar el reporte como asignado")

        now = _now()
        values: dict[str, Any] = {"status": new}
        if new in wf.CLOSED_STATUSES:
            values["closed_at"] = now
        elif old in wf.CLOSED_STATUSES:
            values["closed_at"] = None
        self._set(d, values)
        action = "CIERRE" if new in wf.CLOSED_STATUSES else "CAMBIO_ESTADO"
        self._history(d, actor, action, note=message or wf.PUBLIC_TEXT.get(new), internal=False, old=old, new=new, at=now)
        if internal_note and internal_note.strip():
            self._history(d, actor, "NOTA_INTERNA", note=internal_note.strip(), internal=True)
        self._audit("CAMBIO_ESTADO", d, actor, {"de": old, "a": new})
        return {"status": new}

    def _assign(self, d: dict, actor: Actor, staff: dict, action: str) -> dict:
        old = d["status"]
        new = "ASIGNADO" if old in ("RECIBIDO", "EN_REVISION") else old
        now = _now()
        self._set(d, {"assigned_to": staff["id"], "assigned_name": staff.get("full_name"), "status": new})
        self._history(d, actor, "ASIGNACION", note=f"Asignado a {staff.get('full_name') or 'funcionario'}",
                      internal=True, metadata={"assigned_to": staff["id"]}, at=now)
        if new != old:
            self._history(d, actor, "CAMBIO_ESTADO", note=wf.PUBLIC_TEXT["ASIGNADO"], internal=False, old=old,
                          new=new, at=now)
        self._audit(action, d, actor, {"assigned_to": staff["id"]})
        return {"status": new, "assigned_to": staff["id"], "assigned_name": staff.get("full_name")}

    def take(self, radicado: str, actor: Actor) -> dict:
        d = self._incident(radicado)
        if d.get("assigned_to"):
            raise Conflict("El reporte ya está asignado")
        if not wf.can_take(actor.role, d):
            raise Conflict("El reporte no se puede tomar en su estado actual")
        return self._assign(d, actor, {"id": actor.id, "full_name": actor.full_name}, "TOMAR_INCIDENTE")

    def assign(self, radicado: str, actor: Actor, staff_id: str) -> dict:
        if not wf.is_manager(actor.role):
            raise Forbidden()
        d = self._incident(radicado)
        if d["status"] in wf.CLOSED_STATUSES:
            raise Conflict("Reabra el reporte antes de asignarlo")
        staff = self.directory.get(staff_id)
        if not staff or not staff.get("active") or staff.get("role") not in ("operador", "supervisor", "administrador"):
            raise InvalidData("El funcionario no existe o no está activo")
        return self._assign(d, actor, staff, "ASIGNAR_INCIDENTE")

    def add_note(self, radicado: str, actor: Actor, text: str, public: bool) -> dict:
        d = self._incident(radicado)
        self._require_manage(d, actor)
        action = "MENSAJE_CIUDADANO" if public else "NOTA_INTERNA"
        self._history(d, actor, action, note=text.strip(), internal=not public)
        self._audit(action, d, actor)
        return {"action": action}

    def set_priority(self, radicado: str, actor: Actor, priority: str) -> dict:
        d = self._incident(radicado)
        self._require_manage(d, actor)
        if priority not in wf.PRIORITIES:
            raise InvalidData("Prioridad no válida")
        self.db.incidents.update_one({"_id": d["_id"]}, {"$set": {"priority": priority, "updated_at": _now()}})
        self._history(d, actor, "CAMBIO_PRIORIDAD", note=f"Prioridad {d.get('priority')} → {priority}", internal=True)
        self._audit("CAMBIO_PRIORIDAD", d, actor, {"a": priority})
        return {"priority": priority}

    # ================================================================== tableros
    def summary(self, actor: Actor) -> dict:
        now = _now()
        since = now - timedelta(days=30)
        open_q = {"status": {"$in": list(wf.OPEN_STATUSES)}}
        by_status = Counter(d["status"] for d in self.db.incidents.find(open_q, {"status": 1}))
        recent_docs = list(self.db.incidents.find({"received_at": {"$gte": since}},
                                                  {"received_at": 1, "category_name": 1, "first_response_at": 1}))
        today = _local_day(now)
        days = [today - timedelta(days=i) for i in range(13, -1, -1)]
        per_day = Counter(_local_day(d["received_at"]) for d in recent_docs)
        responses = [(_utc(d["first_response_at"]) - _utc(d["received_at"])).total_seconds() / 60  # type: ignore[operator]
                     for d in recent_docs if d.get("first_response_at")]
        latest = self.db.incidents.find().sort([("received_at", -1), ("radicado", -1)]).limit(8)
        return {
            "open_total": sum(by_status.values()),
            "by_status": {s: by_status.get(s, 0) for s in wf.OPEN_STATUSES},
            "unassigned_open": self.db.incidents.count_documents({**open_q, "assigned_to": None}),
            "mine_open": self.db.incidents.count_documents({**open_q, "assigned_to": actor.id}),
            "high_priority_open": self.db.incidents.count_documents({**open_q, "priority": {"$in": ["ALTA", "CRITICA"]}}),
            "today": per_day.get(today, 0),
            "last_14_days": [{"date": d.isoformat(), "count": per_day.get(d, 0)} for d in days],
            "top_categories_30d": [{"key": k, "count": v} for k, v in
                                   Counter(d.get("category_name", "") for d in recent_docs).most_common(6)],
            "avg_first_response_min": round(sum(responses) / len(responses), 1) if responses else None,
            "recent": [self._row(d) for d in latest],
            "generated_at": now.isoformat(),
        }

    def stats(self, days: int) -> dict:
        since = _now() - timedelta(days=days)
        docs = list(self.db.incidents.find({"received_at": {"$gte": since}}))
        local = [_utc(d["received_at"]).astimezone(BOGOTA) for d in docs]  # type: ignore[union-attr]
        hours_resp = [(_utc(d["first_response_at"]) - _utc(d["received_at"])).total_seconds() / 3600  # type: ignore[operator]
                      for d in docs if d.get("first_response_at")]
        hours_close = [(_utc(d["closed_at"]) - _utc(d["received_at"])).total_seconds() / 3600  # type: ignore[operator]
                       for d in docs if d.get("closed_at")]
        start = _local_day(since)
        per_day = Counter(t.date() for t in local)
        n_days = (_local_day(_now()) - start).days + 1
        by_hour = Counter(t.hour for t in local)
        by_wd = Counter(t.weekday() for t in local)

        def stat(values: list[float]) -> dict:
            return {"avg": round(sum(values) / len(values), 2), "median": round(median(values), 2), "n": len(values)} \
                if values else {"avg": None, "median": None, "n": 0}

        return {
            "days": days, "total": len(docs),
            "by_status": [{"key": k, "count": v} for k, v in Counter(d["status"] for d in docs).most_common()],
            "by_category": [{"key": k, "count": v} for k, v in
                            Counter(d.get("category_name", "") for d in docs).most_common()],
            "by_priority": [{"key": k, "count": v} for k, v in Counter(d.get("priority", "MEDIA") for d in docs).most_common()],
            "by_source": dict(Counter(d.get("source", "") for d in docs)),
            "by_day": [{"date": (start + timedelta(days=i)).isoformat(), "count": per_day.get(start + timedelta(days=i), 0)}
                       for i in range(n_days)],
            "by_hour": [{"key": h, "count": by_hour.get(h, 0)} for h in range(24)],
            "by_weekday": [{"key": WEEKDAYS[i], "count": by_wd.get(i, 0)} for i in range(7)],
            "first_response_hours": stat(hours_resp),
            "resolution_hours": stat(hours_close),
            "out_of_scope": sum(1 for d in docs if d.get("out_of_scope")),
        }

    def map_points(self, f: Filters, actor: Actor) -> dict:
        cur = self.db.incidents.find(self._query(f, actor)).sort("received_at", -1).limit(MAX_MAP_POINTS)
        pts = []
        for d in cur:
            r = self._row(d)
            pts.append({k: r[k] for k in ("radicado", "lat", "lon", "status", "category", "priority", "received_at",
                                          "assigned_name")})
        return {"points": pts, "truncated": len(pts) >= MAX_MAP_POINTS}

    def team(self) -> list[dict]:
        return sorted(({"id": s["id"], "full_name": s.get("full_name"), "role": s["role"]}
                       for s in self.directory.staff() if s.get("active")), key=lambda s: (s["full_name"] or ""))

    # ================================================================== exportación
    def export_csv(self, f: Filters, actor: Actor) -> str:
        cols = ["radicado", "fecha_recepcion", "fecha_ocurrencia", "categoria", "estado", "prioridad", "fuente",
                "latitud", "longitud", "direccion", "asignado_a", "fuera_de_ambito", "descripcion"]
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(cols)
        n = 0
        for d in self.db.incidents.find(self._query(f, actor)).sort("received_at", -1).limit(50_000):
            r = self._row(d)
            w.writerow([_safe(v) for v in (
                r["radicado"], r["received_at"], r["occurred_at"], r["category"], r["status"], r["priority"],
                r["source"], r["lat"], r["lon"], r["address_text"] or "", r["assigned_name"] or "",
                "si" if r["out_of_scope"] else "no", d.get("description", ""))])
            n += 1
        self._audit("EXPORTAR_INCIDENTES", None, actor, {"filas": n})
        return "﻿" + buf.getvalue()  # BOM: Excel abre bien las tildes


def _safe(v: Any) -> Any:
    """Neutraliza inyección de fórmulas en hojas de cálculo."""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v
