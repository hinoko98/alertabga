"""Contraseñas (scrypt de la biblioteca estándar) y tokens de sesión de la app ciudadana."""

import base64
import hashlib
import hmac
import secrets
import time

import jwt

ISSUER = "alertabga-api"
AUDIENCE = "alertabga-ciudadano"
_N, _R, _P = 2**14, 8, 1


def _b64(b: bytes) -> str:
    return base64.b64encode(b).decode()


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    return f"scrypt${_N}${_R}${_P}${_b64(salt)}${_b64(dk)}"


def verify_password(password: str, stored: str | None) -> bool:
    try:
        algo, n, r, p, salt, dk = (stored or "").split("$")
        if algo != "scrypt":
            return False
        calc = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p),
                              dklen=len(base64.b64decode(dk)))
        return hmac.compare_digest(calc, base64.b64decode(dk))
    except (ValueError, TypeError):
        return False


# Hash de relleno: el login con un correo inexistente cuesta lo mismo que con uno real.
DUMMY_HASH = hash_password(secrets.token_urlsafe(16))


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class InvalidToken(Exception):
    pass


def issue_access_token(citizen_id: str, secret: str, ttl_s: int) -> str:
    if len(secret) < 32:
        raise RuntimeError("CITIZEN_JWT_SECRET debe tener al menos 32 caracteres")
    now = int(time.time())
    return jwt.encode({"sub": citizen_id, "iss": ISSUER, "aud": AUDIENCE, "iat": now, "exp": now + ttl_s,
                       "role": "ciudadano"}, secret, algorithm="HS256")


def decode_access_token(token: str, secret: str) -> str:
    if len(secret) < 32:
        raise InvalidToken("secreto no configurado")
    try:
        payload = jwt.decode(token, secret, algorithms=["HS256"], audience=AUDIENCE, issuer=ISSUER,
                             options={"require": ["sub", "exp", "iss", "aud"]})
    except jwt.PyJWTError as e:
        raise InvalidToken(str(e)) from e
    return str(payload["sub"])


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def new_reset_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"
