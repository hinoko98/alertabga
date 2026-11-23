from fastapi import Request

from ..config import get_settings
from .repository import SupabaseReportRepository
from .service import ReportService


def get_report_service() -> ReportService:
    """Dependencia FastAPI (se sustituye en pruebas con dependency_overrides)."""
    return ReportService(SupabaseReportRepository(), get_settings().rate_limit_salt)


def client_ip(request: Request) -> str | None:
    # Vercel sobrescribe X-Forwarded-For con la IP real del cliente como primer elemento.
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip() or None
    return request.client.host if request.client else None
