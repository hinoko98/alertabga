"""Panel institucional: bandeja, detalle, gestión, tableros y exportación (personal con JWT de Supabase)."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import Response
from pydantic import BaseModel, Field

from ..deps import STAFF_ROLES, CurrentUser, require_roles
from ..panel import get_panel_service
from ..panel import workflow as wf
from ..panel.service import Actor, Conflict, Filters, Forbidden, InvalidData, NotFound, PanelService

router = APIRouter(prefix="/staff", tags=["panel institucional"])

Staff = Annotated[CurrentUser, Depends(require_roles(*STAFF_ROLES))]
Manager = Annotated[CurrentUser, Depends(require_roles("supervisor", "administrador"))]
Svc = Annotated[PanelService, Depends(get_panel_service)]


class StatusIn(BaseModel):
    status: str = Field(max_length=20)
    public_message: str | None = Field(default=None, max_length=1000)
    internal_note: str | None = Field(default=None, max_length=2000)


class AssignIn(BaseModel):
    staff_id: str = Field(max_length=64)


class NoteIn(BaseModel):
    text: str = Field(min_length=2, max_length=2000)
    public: bool = False


class PriorityIn(BaseModel):
    priority: str = Field(max_length=10)


def _actor(u: CurrentUser) -> Actor:
    return Actor(u.id, u.role, u.full_name)


def _call(fn):
    try:
        return fn()
    except NotFound as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Reporte no encontrado") from e
    except Forbidden as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "No tiene permiso para gestionar este reporte") from e
    except Conflict as e:
        raise HTTPException(status.HTTP_409_CONFLICT, str(e)) from e
    except InvalidData as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from e


def filters(
    status_: Annotated[str | None, Query(alias="status", max_length=120)] = None,
    category_id: Annotated[str | None, Query(max_length=64)] = None,
    priority: Annotated[str | None, Query(max_length=10)] = None,
    assigned: Annotated[str | None, Query(max_length=64)] = None,
    q: Annotated[str | None, Query(max_length=80)] = None,
    date_from: Annotated[date | None, Query(alias="from")] = None,
    date_to: Annotated[date | None, Query(alias="to")] = None,
    days: Annotated[int | None, Query(ge=1, le=3650)] = None,
) -> Filters:
    statuses = [s for s in (status_ or "").split(",") if s] or None
    if statuses and any(s not in wf.STATUSES for s in statuses):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Estado no válido")
    if priority and priority not in wf.PRIORITIES:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Prioridad no válida")
    return Filters(statuses, category_id, priority, assigned, q, date_from, date_to, days)


F = Annotated[Filters, Depends(filters)]


@router.get("/incidents")
def list_incidents(user: Staff, svc: Svc, f: F, page: int = Query(default=1, ge=1, le=10_000),
                   page_size: int = Query(default=25, ge=1, le=100)) -> dict:
    return svc.list_incidents(f, _actor(user), page, page_size)


@router.get("/incidents.csv")
def export_csv(user: Manager, svc: Svc, f: F) -> Response:
    body = svc.export_csv(f, _actor(user))
    return Response(body, media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": 'attachment; filename="alertabga-incidentes.csv"',
                             "Cache-Control": "no-store"})


@router.get("/incidents/{radicado}")
def detail(radicado: str, request: Request, user: Staff, svc: Svc) -> dict:
    return _call(lambda: svc.detail(radicado, _actor(user), request.url.hostname))


@router.post("/incidents/{radicado}/status")
def change_status(radicado: str, body: StatusIn, user: Staff, svc: Svc) -> dict:
    return _call(lambda: svc.change_status(radicado, _actor(user), body.status, body.public_message, body.internal_note))


@router.post("/incidents/{radicado}/take")
def take(radicado: str, user: Staff, svc: Svc) -> dict:
    return _call(lambda: svc.take(radicado, _actor(user)))


@router.post("/incidents/{radicado}/assign")
def assign(radicado: str, body: AssignIn, user: Staff, svc: Svc) -> dict:
    return _call(lambda: svc.assign(radicado, _actor(user), body.staff_id))


@router.post("/incidents/{radicado}/notes", status_code=status.HTTP_201_CREATED)
def add_note(radicado: str, body: NoteIn, user: Staff, svc: Svc) -> dict:
    return _call(lambda: svc.add_note(radicado, _actor(user), body.text, body.public))


@router.post("/incidents/{radicado}/priority")
def set_priority(radicado: str, body: PriorityIn, user: Staff, svc: Svc) -> dict:
    return _call(lambda: svc.set_priority(radicado, _actor(user), body.priority))


@router.get("/summary")
def summary(user: Staff, svc: Svc) -> dict:
    return svc.summary(_actor(user))


@router.get("/stats")
def stats(_: Manager, svc: Svc, days: int = Query(default=30, ge=1, le=3650)) -> dict:
    return svc.stats(days)


@router.get("/map")
def map_points(user: Staff, svc: Svc, f: F) -> dict:
    return svc.map_points(f, _actor(user))


@router.get("/team")
def team(_: Staff, svc: Svc) -> list[dict]:
    return svc.team()
