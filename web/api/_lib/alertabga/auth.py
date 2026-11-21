"""Validación de JWT emitidos por Supabase Auth (HS256 con secreto, o asimétrico vía JWKS)."""

from functools import lru_cache

import jwt
from pydantic import BaseModel

from .config import Settings

AUDIENCE = "authenticated"


class AuthError(Exception):
    """Token ausente, inválido o vencido. Nunca se expone el motivo al cliente."""


class Claims(BaseModel):
    sub: str
    role: str
    email: str | None = None
    exp: int


@lru_cache(maxsize=4)
def _jwks_client(supabase_url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(f"{supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json", cache_keys=True)


def verify_jwt(token: str, settings: Settings) -> Claims:
    try:
        header = jwt.get_unverified_header(token)
        alg = header.get("alg")
        if alg == "HS256":
            if not settings.supabase_jwt_secret:
                raise AuthError("HS256 sin secreto configurado")
            payload = jwt.decode(token, settings.supabase_jwt_secret, algorithms=["HS256"], audience=AUDIENCE)
        elif alg in ("ES256", "RS256"):
            key = _jwks_client(settings.supabase_url).get_signing_key_from_jwt(token)
            payload = jwt.decode(token, key.key, algorithms=[alg], audience=AUDIENCE)
        else:
            raise AuthError("algoritmo no permitido")
        claims = Claims.model_validate(payload)
    except AuthError:
        raise
    except Exception as exc:  # firma, expiración, formato, red JWKS
        raise AuthError(str(exc)) from exc
    if claims.role != "authenticated":
        raise AuthError("rol de token no autenticado")
    return claims
