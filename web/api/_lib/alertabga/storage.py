"""Cloudflare R2 (API S3). Solo el servidor conoce las claves; los clientes reciben URLs firmadas cortas."""

from functools import lru_cache

import boto3
from botocore.config import Config

from .config import Settings, get_settings

ALLOWED_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_BYTES = 5 * 1024 * 1024
DEFAULT_TTL = 300


class StorageNotConfigured(RuntimeError):
    pass


@lru_cache
def _s3():
    s: Settings = get_settings()
    if not s.r2_configured:
        raise StorageNotConfigured("R2 no configurado")
    return boto3.client(
        "s3",
        endpoint_url=f"https://{s.r2_account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=s.r2_access_key_id,
        aws_secret_access_key=s.r2_secret_access_key,
        region_name="auto",
        config=Config(signature_version="s3v4"),
    )


def presign_put(key: str, mime: str, size: int, ttl: int = DEFAULT_TTL) -> str:
    if mime not in ALLOWED_MIME:
        raise ValueError("Tipo de archivo no permitido")
    if size <= 0 or size > MAX_BYTES:
        raise ValueError("Tamaño de archivo no permitido")
    return _s3().generate_presigned_url(
        "put_object",
        Params={"Bucket": get_settings().r2_bucket, "Key": key, "ContentType": mime, "ContentLength": size},
        ExpiresIn=ttl,
    )


def presign_get(key: str, ttl: int = DEFAULT_TTL) -> str:
    return _s3().generate_presigned_url(
        "get_object", Params={"Bucket": get_settings().r2_bucket, "Key": key}, ExpiresIn=ttl
    )
