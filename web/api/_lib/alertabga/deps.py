"""Dependencias FastAPI: usuario actual y control de roles (RBAC antes de RLS)."""

from collections.abc import Callable, Iterable

from fastapi import Depends, Header, HTTPException, status
from pydantic import BaseModel

from .auth import AuthError, verify_jwt
from .config import get_settings
from .supabase_client import user_client

STAFF_ROLES = frozenset({"operador", "supervisor", "administrador"})


class CurrentUser(BaseModel):
    id: str
    role: str
    full_name: str | None
    token: str


def fetch_profile(token: str, user_id: str) -> dict | None:
    res = (user_client(token).table("profiles")
           .select("id, role_code, full_name, active").eq("id", user_id).limit(1).execute())
    return res.data[0] if res.data else None


def get_current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AuthError("sin token")
    token = authorization.split(" ", 1)[1].strip()
    claims = verify_jwt(token, get_settings())
    profile = fetch_profile(token, claims.sub)
    if profile is None:
        raise AuthError("perfil inexistente")
    if not profile.get("active", False):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cuenta inactiva")
    return CurrentUser(id=claims.sub, role=profile["role_code"], full_name=profile.get("full_name"), token=token)


def ensure_role(user: CurrentUser, roles: Iterable[str]) -> CurrentUser:
    if user.role not in set(roles):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Permiso insuficiente")
    return user


def require_roles(*roles: str) -> Callable[[CurrentUser], CurrentUser]:
    def _dep(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        return ensure_role(user, roles)

    return _dep
