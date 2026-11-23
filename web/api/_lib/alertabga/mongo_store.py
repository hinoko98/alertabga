"""Colecciones operativas de la app ciudadana en MongoDB (ADR 0003): índices, rate limit y auditoría."""

from datetime import UTC, datetime, timedelta
from typing import Any

from pymongo import ASCENDING, DESCENDING, ReturnDocument

from .mongo import get_db

_indexed: set[int] = set()


class MongoUnavailable(RuntimeError):
    pass


def operational_db() -> Any:
    db = get_db()
    if db is None:
        raise MongoUnavailable("MongoDB no configurado")
    ensure_indexes(db)
    return db


def ensure_indexes(db: Any) -> None:
    """Idempotente; se ejecuta una vez por proceso y base."""
    if id(db) in _indexed:
        return
    db.citizens.create_index("email", unique=True)
    db.citizen_sessions.create_index("expires_at", expireAfterSeconds=0)
    db.citizen_sessions.create_index("citizen_id")
    db.incidents.create_index("radicado", unique=True)
    db.incidents.create_index([("reporter_id", ASCENDING), ("received_at", DESCENDING)])
    db.incidents.create_index([("received_at", DESCENDING)])
    db.incidents.create_index("status")
    db.incidents.create_index([("location", "2dsphere")])
    db.incident_history.create_index([("incident_id", ASCENDING), ("created_at", ASCENDING), ("seq", ASCENDING)])
    db.evidence.create_index("incident_id")
    db.evidence.create_index("storage_key", unique=True)
    db.rate_limits.create_index("expires_at", expireAfterSeconds=0)
    db.audit_logs.create_index([("entity", ASCENDING), ("entity_id", ASCENDING)])
    db.audit_logs.create_index([("created_at", DESCENDING)])
    _indexed.add(id(db))


def hit_rate_limit(db: Any, key: str, max_hits: int, window_minutes: int, now: datetime | None = None) -> bool:
    """Ventana fija persistente. Devuelve False si se excede el máximo."""
    now = now or datetime.now(UTC)
    secs = max(1, int(window_minutes)) * 60
    start = int(now.timestamp()) // secs * secs
    doc = db.rate_limits.find_one_and_update(
        {"_id": f"{key}|{start}"},
        {"$inc": {"hits": 1},
         "$setOnInsert": {"expires_at": datetime.fromtimestamp(start, UTC) + timedelta(seconds=secs * 2)}},
        upsert=True, return_document=ReturnDocument.AFTER,
    )
    return int(doc["hits"]) <= max_hits


def write_audit(db: Any, action: str, entity: str, entity_id: str | None, actor_id: str | None,
                actor_role: str | None, metadata: dict | None = None, ip_hash: str | None = None) -> None:
    db.audit_logs.insert_one({
        "action": action, "entity": entity, "entity_id": entity_id, "actor_id": actor_id,
        "actor_role": actor_role, "metadata": metadata or {}, "ip_hash": ip_hash,
        "created_at": datetime.now(UTC),
    })
