"""MongoDB (histórico y agregados oficiales). Conexión reutilizada por instancia serverless."""

from functools import lru_cache
from typing import Any

from pymongo import MongoClient

from .config import get_settings


@lru_cache
def _client() -> MongoClient | None:
    s = get_settings()
    if not s.mongodb_uri:
        return None
    return MongoClient(s.mongodb_uri, serverSelectionTimeoutMS=3000, appname="alertabga-api")


def get_db() -> Any | None:
    client = _client()
    return client[get_settings().mongodb_db] if client else None


def ping() -> bool:
    client = _client()
    if client is None:
        return False
    try:
        client.admin.command("ping")
        return True
    except Exception:
        return False
