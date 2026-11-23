"""Administración del panel: solo rol administrador (además, la RLS lo exige en Supabase)."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from ..admin import AdminService, Conflict, InvalidData, NotFound, SupabaseAdminGateway
from ..deps import CurrentUser, require_roles

router = APIRouter(prefix="/admin", tags=["administración"])

Admin = Annotated[CurrentUser, Depends(require_roles("administrador"))]


def get_admin_service(user: Admin) -> AdminService:
    from ..mongo_store import MongoUnavailable, operational_db

    try:
        db = operational_db()
    except MongoUnavailable:
        db = None
    return AdminService(SupabaseAdminGateway(user.token), db, user.id)


Svc = Annotated[AdminService, Depends(get_admin_service)]


class StaffIn(BaseModel):
    email: str = Field(max_length=254)
    full_name: str = Field(max_length=120)
    role: str = Field(max_length=20)
    password: str | None = Field(default=None, max_length=128)


class StaffPatch(BaseModel):
    role: str | None = Field(default=None, max_length=20)
    active: bool | None = None
    full_name: str | None = Field(default=None, max_length=120)


class CategoryIn(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    description: str | None = Field(default=None, max_length=300)
    color: str | None = Field(default=None, max_length=7)
    icon: str | None = Field(default=None, max_length=40)
    severity_default: int | None = None
    active: bool | None = None


class RateLimitIn(BaseModel):
    max: int
    window_minutes: int


def _call(fn):
    try:
        return fn()
    except InvalidData as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from e
    except Conflict as e:
        raise HTTPException(status.HTTP_409_CONFLICT, str(e)) from e
    except NotFound as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No encontrado") from e


@router.get("/users")
def users(svc: Svc) -> list[dict]:
    return svc.users()


@router.post("/users", status_code=status.HTTP_201_CREATED)
def create_user(body: StaffIn, svc: Svc) -> dict:
    return _call(lambda: svc.create_staff(body.email, body.full_name, body.role, body.password))


@router.patch("/users/{user_id}")
def update_user(user_id: str, body: StaffPatch, svc: Svc) -> dict:
    return _call(lambda: svc.update_staff(user_id, body.role, body.active, body.full_name))


@router.get("/categories")
def categories(svc: Svc) -> list[dict]:
    return svc.categories()


@router.post("/categories", status_code=status.HTTP_201_CREATED)
def create_category(body: CategoryIn, svc: Svc) -> dict:
    return _call(lambda: svc.create_category(body.model_dump(exclude_none=True)))


@router.patch("/categories/{category_id}")
def update_category(category_id: str, body: CategoryIn, svc: Svc) -> dict:
    return _call(lambda: svc.update_category(category_id, body.model_dump(exclude_none=True)))


@router.get("/settings")
def settings(svc: Svc) -> dict:
    return svc.settings()


@router.put("/settings/rate-limit")
def update_rate_limit(body: RateLimitIn, svc: Svc) -> dict:
    return _call(lambda: svc.update_rate_limit(body.max, body.window_minutes))


@router.get("/audit")
def audit(svc: Svc, limit: int = Query(default=100, ge=1, le=500),
          action: str | None = Query(default=None, max_length=40)) -> list[dict]:
    names = {u["id"]: u.get("full_name") or u.get("email") or "—" for u in svc.users()}
    return svc.audit_log(limit, action, names)


@router.get("/citizens")
def citizens(svc: Svc) -> dict:
    return svc.citizens_summary()
