from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field, field_validator

from ..citizens import CurrentCitizen, get_citizen_service, get_current_citizen
from ..citizens.security import sha256
from ..citizens.service import AuthFailed, CitizenService, InvalidData, TooManyAttempts
from ..config import get_settings
from ..reports import client_ip

router = APIRouter(tags=["cuenta ciudadana"])


class RegisterIn(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=72)
    full_name: str = Field(max_length=120)


class LoginIn(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=72)


class RefreshIn(BaseModel):
    refresh_token: str = Field(max_length=200)


class ForgotIn(BaseModel):
    email: str = Field(max_length=254)


class ResetIn(BaseModel):
    email: str = Field(max_length=254)
    code: str = Field(max_length=10)
    new_password: str = Field(max_length=72)


class ChangePasswordIn(BaseModel):
    current_password: str = Field(max_length=72)
    new_password: str = Field(max_length=72)


class ProfileIn(BaseModel):
    full_name: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=20)
    notify_status_changes: bool | None = None

    @field_validator("full_name")
    @classmethod
    def _name(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if len(v) < 3:
            raise ValueError("Ingrese su nombre")
        return v

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str | None) -> str | None:
        import re

        if v is None or not v.strip():
            return None
        if not re.fullmatch(r"\+?[0-9 ]{7,20}", v.strip()):
            raise ValueError("Teléfono no válido")
        return v.strip()


def _ip_key(request: Request) -> str:
    return sha256(f"{get_settings().rate_limit_salt}|{client_ip(request) or ''}")[:24]


def _call(fn):
    try:
        return fn()
    except InvalidData as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from e
    except TooManyAttempts as e:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Demasiados intentos. Espere unos minutos.") from e


@router.post("/auth/register", status_code=status.HTTP_201_CREATED)
def register(body: RegisterIn, svc: CitizenService = Depends(get_citizen_service)) -> dict:
    return _call(lambda: svc.register(body.email, body.password, body.full_name))


@router.post("/auth/login")
def login(body: LoginIn, request: Request, svc: CitizenService = Depends(get_citizen_service)) -> dict:
    try:
        return _call(lambda: svc.login(body.email, body.password, _ip_key(request)))
    except AuthFailed as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Correo o contraseña incorrectos") from e


@router.post("/auth/refresh")
def refresh(body: RefreshIn, svc: CitizenService = Depends(get_citizen_service)) -> dict:
    try:
        return svc.refresh(body.refresh_token)
    except AuthFailed as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sesión vencida") from e


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: RefreshIn, svc: CitizenService = Depends(get_citizen_service)) -> None:
    svc.logout(body.refresh_token)


@router.post("/auth/password/forgot", status_code=status.HTTP_202_ACCEPTED)
def forgot(body: ForgotIn, request: Request, svc: CitizenService = Depends(get_citizen_service)) -> dict:
    _call(lambda: svc.forgot(body.email, _ip_key(request)))
    return {"detail": "Si el correo está registrado, recibirá un código de 6 dígitos."}


@router.post("/auth/password/reset")
def reset(body: ResetIn, svc: CitizenService = Depends(get_citizen_service)) -> dict:
    try:
        return _call(lambda: svc.reset(body.email, body.code, body.new_password))
    except AuthFailed as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Código inválido o vencido") from e


@router.get("/account")
def account(me: CurrentCitizen = Depends(get_current_citizen),
            svc: CitizenService = Depends(get_citizen_service)) -> dict:
    return svc.profile(me.id)


@router.patch("/account")
def update_account(body: ProfileIn, me: CurrentCitizen = Depends(get_current_citizen),
                   svc: CitizenService = Depends(get_citizen_service)) -> dict:
    return svc.update_profile(me.id, body.model_dump(exclude_unset=True))


@router.post("/account/password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(body: ChangePasswordIn, me: CurrentCitizen = Depends(get_current_citizen),
                    svc: CitizenService = Depends(get_citizen_service)) -> None:
    try:
        _call(lambda: svc.change_password(me.id, body.current_password, body.new_password))
    except AuthFailed as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "La contraseña actual no es correcta") from e
