"""Almacenamiento privado de evidencias (Cloudflare R2 vía API S3; en local, Supabase Storage S3).

Solo el servidor conoce las claves. Los clientes reciben URLs firmadas de corta duración.
Se usan dos clientes: uno interno (HEAD/DELETE desde la API) y otro que firma con el host público
que verá el teléfono o el navegador (la firma S3v4 incluye el host).
"""

from functools import lru_cache

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from .config import get_settings

ALLOWED_MIME = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
MAX_BYTES = 5 * 1024 * 1024
DEFAULT_TTL = 300


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


@lru_cache
def _signer():
    s = get_settings()
    if not s.r2_configured:
        raise StorageNotConfigured("Almacenamiento de evidencias no configurado")
    return _make(s.r2_public_endpoint_url or s.r2_endpoint)  # type: ignore[arg-type]


def reset_clients() -> None:
    _internal.cache_clear()
    _signer.cache_clear()


def extension_for(mime: str) -> str:
    if mime not in ALLOWED_MIME:
        raise ValueError("Tipo de archivo no permitido")
    return ALLOWED_MIME[mime]


def validate(mime: str, size: int) -> None:
    extension_for(mime)
    if size <= 0 or size > MAX_BYTES:
        raise ValueError("Tamaño de archivo no permitido (máximo 5 MB)")


def presign_put(key: str, mime: str, size: int, ttl: int = DEFAULT_TTL) -> str:
    validate(mime, size)
    return _signer().generate_presigned_url(
        "put_object",
        Params={"Bucket": get_settings().r2_bucket, "Key": key, "ContentType": mime, "ContentLength": size},
        ExpiresIn=ttl,
    )


def presign_get(key: str, ttl: int = DEFAULT_TTL) -> str:
    return _signer().generate_presigned_url(
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
