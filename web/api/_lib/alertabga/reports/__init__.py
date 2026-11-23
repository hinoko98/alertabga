from fastapi import HTTPException, Request, status

from ..config import get_settings
from ..mongo_store import MongoUnavailable, operational_db
from .repository import MongoReportRepository, SupabaseConfig
from .service import ReportService


def get_report_service() -> ReportService:
    """Dependencia FastAPI (se sustituye en pruebas con dependency_overrides)."""
    try:
        db = operational_db()
    except MongoUnavailable as e:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Servicio no disponible") from e
    return ReportService(MongoReportRepository(db, SupabaseConfig()), get_settings().rate_limit_salt)


def client_ip(request: Request) -> str | None:
    # Vercel sobrescribe X-Forwarded-For con la IP real del cliente como primer elemento.
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip() or None
    return request.client.host if request.client else None
