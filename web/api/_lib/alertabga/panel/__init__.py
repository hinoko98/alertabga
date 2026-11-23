"""Panel institucional (Fase 3): dependencias FastAPI."""

from fastapi import HTTPException, status

from ..mongo_store import MongoUnavailable, operational_db
from .service import PanelService


class SupabaseStaffDirectory:
    """Personal activo (perfiles de Supabase con rol institucional), leído con service role."""

    ROLES = ("operador", "supervisor", "administrador")

    def __init__(self) -> None:
        self._cache: list[dict] | None = None  # una consulta por petición

    def staff(self) -> list[dict]:
        from ..supabase_client import service_client

        if self._cache is not None:
            return self._cache
        res = (service_client().table("profiles").select("id, full_name, role_code, active")
               .in_("role_code", list(self.ROLES)).execute())
        self._cache = [{"id": r["id"], "full_name": r.get("full_name"), "role": r["role_code"], "active": r["active"]}
                       for r in res.data or []]
        return self._cache

    def get(self, staff_id: str) -> dict | None:
        return next((s for s in self.staff() if s["id"] == staff_id), None)


def get_panel_service() -> PanelService:
    from .. import storage

    try:
        db = operational_db()
    except MongoUnavailable as e:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Base operativa no disponible") from e
    return PanelService(db, SupabaseStaffDirectory(), storage)
