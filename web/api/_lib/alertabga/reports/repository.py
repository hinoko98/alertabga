"""Acceso a datos de reportes. La API autoriza antes de llamar aquí; el cliente de servicio se usa
solo para operaciones que el ciudadano no puede hacer directamente (crear, seguimiento anónimo)."""

from typing import Any, Protocol

from ..supabase_client import service_client, user_client

PUBLIC_ACTIONS = ("CREADO", "CAMBIO_ESTADO", "CIERRE", "MENSAJE_CIUDADANO")


class ReportRepository(Protocol):
    def active_category(self, category_id: str) -> dict | None: ...
    def active_categories(self) -> list[dict]: ...
    def rate_limit_setting(self) -> dict: ...
    def hit_rate_limit(self, key: str, max_hits: int, window_minutes: int) -> bool: ...
    def insert_incident(self, row: dict[str, Any]) -> dict: ...
    def find_by_radicado(self, radicado: str) -> dict | None: ...
    def public_timeline(self, incident_id: str) -> list[dict]: ...
    def list_mine(self, token: str, user_id: str) -> list[dict]: ...
    def count_evidence(self, incident_id: str, statuses: tuple[str, ...]) -> int: ...
    def insert_evidence(self, row: dict[str, Any]) -> dict: ...
    def find_evidence(self, evidence_id: str, incident_id: str) -> dict | None: ...
    def update_evidence(self, evidence_id: str, values: dict[str, Any]) -> None: ...
    def audit(self, action: str, entity: str, entity_id: str | None, actor_id: str | None,
              actor_role: str | None, metadata: dict | None = None, ip_hash: str | None = None) -> None: ...


class SupabaseReportRepository:
    def __init__(self) -> None:
        self._db = service_client()

    def active_category(self, category_id: str) -> dict | None:
        res = (self._db.table("categories").select("id, name")
               .eq("id", category_id).eq("active", True).limit(1).execute())
        return res.data[0] if res.data else None

    def active_categories(self) -> list[dict]:
        res = (self._db.table("categories").select("id, name, description, icon, color")
               .eq("active", True).order("name").execute())
        return res.data or []

    def rate_limit_setting(self) -> dict:
        res = self._db.table("app_settings").select("value").eq("key", "rate_limit_reports").limit(1).execute()
        return res.data[0]["value"] if res.data else {"max": 5, "window_minutes": 60}

    def hit_rate_limit(self, key: str, max_hits: int, window_minutes: int) -> bool:
        res = self._db.rpc("check_rate_limit", {
            "p_key": key, "p_max": max_hits, "p_window": f"{int(window_minutes)} minutes",
        }).execute()
        return bool(res.data)

    def insert_incident(self, row: dict[str, Any]) -> dict:
        res = (self._db.table("incidents").insert(row)
               .execute())
        r = res.data[0]
        return {k: r[k] for k in ("id", "radicado", "received_at", "status", "out_of_scope")}

    def find_by_radicado(self, radicado: str) -> dict | None:
        res = (self._db.table("incidents")
               .select("id, radicado, status, description, occurred_at, received_at, address_text, "
                       "out_of_scope, source, reporter_id, anon_token_hash, categories(name)")
               .eq("radicado", radicado).limit(1).execute())
        if not res.data:
            return None
        r = res.data[0]
        r["category"] = (r.pop("categories") or {}).get("name", "")
        return r

    def public_timeline(self, incident_id: str) -> list[dict]:
        res = (self._db.table("incident_history")
               .select("action, new_status, note, created_at")
               .eq("incident_id", incident_id).eq("is_internal", False)
               .in_("action", list(PUBLIC_ACTIONS))
               .order("created_at").order("id").execute())
        return res.data or []

    def list_mine(self, token: str, user_id: str) -> list[dict]:
        # Con el JWT del ciudadano: RLS es la barrera final.
        res = (user_client(token).table("incidents")
               .select("radicado, status, received_at, categories(name)")
               .eq("reporter_id", user_id).order("received_at", desc=True).limit(100).execute())
        out = []
        for r in res.data or []:
            r["category"] = (r.pop("categories") or {}).get("name", "")
            out.append(r)
        return out

    def count_evidence(self, incident_id: str, statuses: tuple[str, ...]) -> int:
        res = (self._db.table("evidence").select("id", count="exact")
               .eq("incident_id", incident_id).in_("status", list(statuses)).execute())
        return res.count or 0

    def insert_evidence(self, row: dict[str, Any]) -> dict:
        return self._db.table("evidence").insert(row).execute().data[0]

    def find_evidence(self, evidence_id: str, incident_id: str) -> dict | None:
        res = (self._db.table("evidence").select("id, incident_id, storage_key, mime_type, size_bytes, status")
               .eq("id", evidence_id).eq("incident_id", incident_id).limit(1).execute())
        return res.data[0] if res.data else None

    def update_evidence(self, evidence_id: str, values: dict[str, Any]) -> None:
        self._db.table("evidence").update(values).eq("id", evidence_id).execute()

    def audit(self, action: str, entity: str, entity_id: str | None, actor_id: str | None,
              actor_role: str | None, metadata: dict | None = None, ip_hash: str | None = None) -> None:
        from ..audit import write_audit

        write_audit(action, entity, entity_id, actor_id, actor_role, metadata, ip_hash)
