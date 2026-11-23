from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, Field

from ..deps import CurrentUser, get_current_user
from ..reports import client_ip, get_report_service
from ..reports.evidence_service import EvidenceNotFound, EvidenceService, InvalidFile, NotUploaded, TooManyFiles
from ..reports.service import NotFound, ReportService, Requester
from ..storage import StorageNotConfigured

router = APIRouter(prefix="/evidence", tags=["evidencias"])

NOT_FOUND = "Radicado o código no válido"


class PresignIn(BaseModel):
    radicado: str = Field(max_length=40)
    mime: str = Field(max_length=40)
    size: int
    tracking_token: str | None = Field(default=None, max_length=200)


class ConfirmIn(BaseModel):
    radicado: str = Field(max_length=40)
    tracking_token: str | None = Field(default=None, max_length=200)


def get_evidence_service(reports: ReportService = Depends(get_report_service)) -> EvidenceService:
    return EvidenceService(reports)


def optional_user(authorization: str | None = Header(default=None)) -> CurrentUser | None:
    """Con Bearer válido → ciudadano autenticado; sin Bearer → anónimo (usa tracking_token)."""
    if not authorization:
        return None
    return get_current_user(authorization)


def _requester(request: Request, user: CurrentUser | None, device: str | None) -> Requester:
    ip = client_ip(request)
    if user is None:
        return Requester(ip, device)
    return Requester(ip, device, user.id, user.role, user.token)


def _call(fn):
    try:
        return fn()
    except (NotFound, EvidenceNotFound) as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND) from e
    except InvalidFile as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from e
    except TooManyFiles as e:
        raise HTTPException(status.HTTP_409_CONFLICT, "Máximo 3 fotos por reporte") from e
    except NotUploaded as e:
        raise HTTPException(status.HTTP_409_CONFLICT, "El archivo aún no se ha recibido") from e
    except StorageNotConfigured as e:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Almacenamiento no disponible") from e


@router.post("/presign")
def presign(body: PresignIn, request: Request, user: CurrentUser | None = Depends(optional_user),
            x_device_id: str | None = Header(default=None),
            svc: EvidenceService = Depends(get_evidence_service)) -> dict:
    req = _requester(request, user, x_device_id)
    return _call(lambda: svc.presign(body.radicado, body.mime, body.size, req, body.tracking_token))


@router.post("/{evidence_id}/confirm")
def confirm(evidence_id: str, body: ConfirmIn, request: Request,
            user: CurrentUser | None = Depends(optional_user),
            x_device_id: str | None = Header(default=None),
            svc: EvidenceService = Depends(get_evidence_service)) -> dict:
    req = _requester(request, user, x_device_id)
    return {"status": _call(lambda: svc.confirm(evidence_id, body.radicado, req, body.tracking_token))}

