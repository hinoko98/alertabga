"""Almacenamiento privado de evidencias (Cloudflare R2 vía API S3; en local, Supabase Storage S3).

Solo el servidor conoce las claves. Los clientes reciben URLs firmadas de corta duración.
Se usan dos clientes: uno interno (HEAD/DELETE desde la API) y otro que firma con el host público
que verá el teléfono o el navegador (la firma S3v4 incluye el host).
"""

import re
from functools import lru_cache

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from .config import get_settings

ALLOWED_MIME = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
MAX_BYTES = 5 * 1024 * 1024
DEFAULT_TTL = 300
# Solo nombres de host o IPv4 simples; cualquier otra cosa usa 127.0.0.1.
_HOST_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")


class StorageNotConfigured(RuntimeError):
    pass


def _make(endpoint: str):
    s = get_settings()
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=s.r2_access_key_id,
        aws_secret_access_key=s.r2_secret_access_key,
        region_name=s.r2_region,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


@lru_cache
def _internal():
    s = get_settings()
    if not s.r2_configured:
        raise StorageNotConfigured("Almacenamiento de evidencias no configurado")
    return _make(s.r2_endpoint)  # type: ignore[arg-type]


def public_endpoint(host: str | None = None) -> str:
    """Endpoint con el que se firman las URL para clientes.

    En desarrollo, R2_PUBLIC_ENDPOINT_URL puede contener `{host}`: se usa el host por el que el cliente
    llamó a la API (emulador Android: 10.0.2.2), así el teléfono alcanza el almacenamiento sin
    configuración extra. En producción es una URL fija y `host` se ignora.
    """
    s = get_settings()
    endpoint = s.r2_public_endpoint_url or s.r2_endpoint
    if endpoint and "{host}" in endpoint:
        safe = host if host and _HOST_RE.match(host) else "127.0.0.1"
        endpoint = endpoint.replace("{host}", safe)
    return endpoint  # type: ignore[return-value]


@lru_cache(maxsize=16)
def _signer_for(endpoint: str):
    return _make(endpoint)


def _signer(host: str | None = None):
    s = get_settings()
    if not s.r2_configured:
        raise StorageNotConfigured("Almacenamiento de evidencias no configurado")
    return _signer_for(public_endpoint(host))


def reset_clients() -> None:
    _internal.cache_clear()
    _signer_for.cache_clear()


def extension_for(mime: str) -> str:
    if mime not in ALLOWED_MIME:
        raise ValueError("Tipo de archivo no permitido")
    return ALLOWED_MIME[mime]


def validate(mime: str, size: int) -> None:
    extension_for(mime)
    if size <= 0 or size > MAX_BYTES:
        raise ValueError("Tamaño de archivo no permitido (máximo 5 MB)")


def presign_put(key: str, mime: str, size: int, ttl: int = DEFAULT_TTL, host: str | None = None) -> str:
    validate(mime, size)
    return _signer(host).generate_presigned_url(
        "put_object",
        Params={"Bucket": get_settings().r2_bucket, "Key": key, "ContentType": mime, "ContentLength": size},
        ExpiresIn=ttl,
    )


def presign_get(key: str, ttl: int = DEFAULT_TTL, host: str | None = None) -> str:
    return _signer(host).generate_presigned_url(
        "get_object", Params={"Bucket": get_settings().r2_bucket, "Key": key}, ExpiresIn=ttl
    )


def head(key: str) -> dict | None:
    try:
        h = _internal().head_object(Bucket=get_settings().r2_bucket, Key=key)
    except ClientError:
        return None
    return {"size": int(h["ContentLength"]), "mime": h.get("ContentType", "")}


def delete(key: str) -> None:
    _internal().delete_object(Bucket=get_settings().r2_bucket, Key=key)
