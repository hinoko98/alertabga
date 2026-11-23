"""Cuentas de la app ciudadana en MongoDB: registro, ingreso, sesiones rotativas, recuperación y perfil.
Ningún mensaje revela si un correo está registrado."""

import re
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from pymongo.errors import DuplicateKeyError

from ..config import Settings
from ..mongo_store import hit_rate_limit
from . import security as sec
from .mailer import Mailer

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")
LOGIN_MAX, LOGIN_WINDOW_MIN = 10, 15
FORGOT_MAX, FORGOT_WINDOW_MIN = 3, 60
RESET_TTL = timedelta(minutes=15)
RESET_MAX_ATTEMPTS = 5


class AuthFailed(Exception):
    """Credenciales, sesión o código inválidos (mensaje genérico)."""


class TooManyAttempts(Exception):
    pass


class InvalidData(Exception):
    pass


def normalize_email(email: str) -> str:
    e = (email or "").strip().lower()
    if not EMAIL_RE.match(e) or len(e) > 254:
        raise InvalidData("Correo no válido")
    return e


def check_password(pw: str) -> None:
    if not 8 <= len(pw or "") <= 72:
        raise InvalidData("La contraseña debe tener entre 8 y 72 caracteres")


def _now() -> datetime:
    return datetime.now(UTC)


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


class CitizenService:
    def __init__(self, db: Any, settings: Settings, mailer: Mailer) -> None:
        self.db = db
        self.s = settings
        self.mailer = mailer

    # ------------------------------------------------------------ sesiones
    def _session(self, citizen_id: str) -> dict:
        refresh = sec.new_refresh_token()
        self.db.citizen_sessions.insert_one({
            "_id": sec.sha256(refresh), "citizen_id": citizen_id, "created_at": _now(),
            "expires_at": _now() + timedelta(days=self.s.citizen_refresh_ttl_days),
        })
        return {
            "access_token": sec.issue_access_token(citizen_id, self.s.citizen_jwt_secret, self.s.citizen_access_ttl_s),
            "refresh_token": refresh,
            "token_type": "bearer",
            "expires_in": self.s.citizen_access_ttl_s,
        }

    def register(self, email: str, password: str, full_name: str) -> dict:
        email = normalize_email(email)
        check_password(password)
        name = (full_name or "").strip()
        if not 3 <= len(name) <= 120:
            raise InvalidData("Ingrese su nombre (3 a 120 caracteres)")
        cid = str(uuid.uuid4())
        try:
            self.db.citizens.insert_one({
                "_id": cid, "email": email, "password_hash": sec.hash_password(password), "full_name": name,
                "phone": None, "notify_status_changes": False, "active": True,
                "created_at": _now(), "updated_at": _now(),
            })
        except DuplicateKeyError as e:
            raise InvalidData("No fue posible crear la cuenta con ese correo") from e
        return self._session(cid)

    def login(self, email: str, password: str, ip_key: str) -> dict:
        e = (email or "").strip().lower()
        if not hit_rate_limit(self.db, f"login:{sec.sha256(e)}:{ip_key}", LOGIN_MAX, LOGIN_WINDOW_MIN):
            raise TooManyAttempts()
        doc = self.db.citizens.find_one({"email": e})
        ok = sec.verify_password(password or "", doc["password_hash"] if doc else sec.DUMMY_HASH)
        if not doc or not ok or not doc.get("active", False):
            raise AuthFailed()
        return self._session(doc["_id"])

    def refresh(self, refresh_token: str) -> dict:
        """Rotación: el refresh usado se borra; reusar uno viejo falla."""
        sess = self.db.citizen_sessions.find_one_and_delete({"_id": sec.sha256(refresh_token or "")})
        if not sess or _aware(sess["expires_at"]) < _now():
            raise AuthFailed()
        doc = self.db.citizens.find_one({"_id": sess["citizen_id"], "active": True})
        if not doc:
            raise AuthFailed()
        return self._session(doc["_id"])

    def logout(self, refresh_token: str) -> None:
        self.db.citizen_sessions.delete_one({"_id": sec.sha256(refresh_token or "")})

    def active_citizen(self, citizen_id: str) -> dict | None:
        return self.db.citizens.find_one({"_id": citizen_id, "active": True}, {"password_hash": 0, "reset": 0})

    # ------------------------------------------------------------ recuperación de contraseña
    def forgot(self, email: str, ip_key: str) -> None:
        try:
            e = normalize_email(email)
        except InvalidData:
            return
        if not hit_rate_limit(self.db, f"forgot:{sec.sha256(e)}:{ip_key}", FORGOT_MAX, FORGOT_WINDOW_MIN):
            raise TooManyAttempts()
        doc = self.db.citizens.find_one({"email": e, "active": True})
        if not doc:
            return
        code = sec.new_reset_code()
        self.db.citizens.update_one({"_id": doc["_id"]}, {"$set": {"reset": {
            "code_hash": sec.sha256(f"{doc['_id']}:{code}"), "expires_at": _now() + RESET_TTL, "attempts": 0}}})
        self.mailer.send(e, "AlertaBGA — código para cambiar su contraseña",
                         f"Su código es {code}. Vence en 15 minutos.\n"
                         "Si usted no lo solicitó, ignore este mensaje; su contraseña no cambia.")

    def reset(self, email: str, code: str, new_password: str) -> dict:
        check_password(new_password)
        e = (email or "").strip().lower()
        doc = self.db.citizens.find_one({"email": e, "active": True})
        r = (doc or {}).get("reset")
        if not doc or not r or _aware(r["expires_at"]) < _now() or r.get("attempts", 0) >= RESET_MAX_ATTEMPTS:
            raise AuthFailed()
        if sec.sha256(f"{doc['_id']}:{(code or '').strip()}") != r["code_hash"]:
            self.db.citizens.update_one({"_id": doc["_id"]}, {"$inc": {"reset.attempts": 1}})
            raise AuthFailed()
        self.db.citizens.update_one({"_id": doc["_id"]}, {
            "$set": {"password_hash": sec.hash_password(new_password), "updated_at": _now()}, "$unset": {"reset": ""}})
        self.db.citizen_sessions.delete_many({"citizen_id": doc["_id"]})  # cierra las demás sesiones
        return self._session(doc["_id"])

    def change_password(self, citizen_id: str, current: str, new_password: str) -> None:
        check_password(new_password)
        doc = self.db.citizens.find_one({"_id": citizen_id, "active": True})
        if not doc or not sec.verify_password(current or "", doc["password_hash"]):
            raise AuthFailed()
        self.db.citizens.update_one({"_id": citizen_id}, {
            "$set": {"password_hash": sec.hash_password(new_password), "updated_at": _now()}})

    # ------------------------------------------------------------ perfil
    def profile(self, citizen_id: str) -> dict:
        doc = self.active_citizen(citizen_id)
        if not doc:
            raise AuthFailed()
        return {"id": doc["_id"], "email": doc["email"], "full_name": doc.get("full_name"),
                "phone": doc.get("phone"), "notify_status_changes": bool(doc.get("notify_status_changes"))}

    def update_profile(self, citizen_id: str, values: dict) -> dict:
        allowed = {k: v for k, v in values.items() if k in ("full_name", "phone", "notify_status_changes")}
        if allowed:
            allowed["updated_at"] = _now()
            self.db.citizens.update_one({"_id": citizen_id, "active": True}, {"$set": allowed})
        return self.profile(citizen_id)
