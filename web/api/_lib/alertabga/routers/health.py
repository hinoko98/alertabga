from datetime import UTC, datetime

import httpx
from fastapi import APIRouter

from ..config import Settings, get_settings

router = APIRouter(tags=["sistema"])


def check_supabase(settings: Settings) -> bool:
    try:
        r = httpx.get(f"{settings.supabase_url.rstrip('/')}/auth/v1/health",
                      headers={"apikey": settings.supabase_anon_key}, timeout=3)
        return r.status_code == 200
    except httpx.HTTPError:
        return False


def check_mongo(settings: Settings) -> str:
    if not settings.mongodb_uri:
        return "no_configurado"
    from ..mongo import ping

    return "ok" if ping() else "error"


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "alertabga-api", "time": datetime.now(UTC).isoformat()}


@router.get("/health/deps")
def health_deps() -> dict:
    s = get_settings()
    return {
        "supabase": "ok" if check_supabase(s) else "error",
        "r2": "configurado" if s.r2_configured else "no_configurado",
        "mongodb": check_mongo(s),
        "time": datetime.now(UTC).isoformat(),
    }
