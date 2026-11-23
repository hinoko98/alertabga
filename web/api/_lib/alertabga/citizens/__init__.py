from fastapi import Depends, Header, HTTPException, status
from pydantic import BaseModel

from ..auth import AuthError
from ..config import get_settings
from ..mongo_store import MongoUnavailable, operational_db
from .mailer import SmtpMailer
from .security import InvalidToken, decode_access_token
from .service import CitizenService


class CurrentCitizen(BaseModel):
    id: str
    role: str = "ciudadano"


def get_citizen_service() -> CitizenService:
    try:
        db = operational_db()
    except MongoUnavailable as e:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Servicio no disponible") from e
    s = get_settings()
    return CitizenService(db, s, SmtpMailer(s))


def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AuthError("sin token")
    return authorization.split(" ", 1)[1].strip()


def get_current_citizen(authorization: str | None = Header(default=None),
                        svc: CitizenService = Depends(get_citizen_service)) -> CurrentCitizen:
    """Ciudadano autenticado con el JWT emitido por esta API (no por Supabase)."""
    try:
        cid = decode_access_token(_bearer(authorization), get_settings().citizen_jwt_secret)
    except InvalidToken as e:
        raise AuthError(str(e)) from e
    if svc.active_citizen(cid) is None:
        raise AuthError("cuenta inexistente o inactiva")
    return CurrentCitizen(id=cid)


def optional_citizen(authorization: str | None = Header(default=None),
                     svc: CitizenService = Depends(get_citizen_service)) -> CurrentCitizen | None:
    if not authorization:
        return None
    return get_current_citizen(authorization, svc)
