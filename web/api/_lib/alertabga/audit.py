"""Registro de auditoría (solo inserción, con service role). La IP se guarda como hash, nunca en claro."""

import hashlib
from typing import Any

from .supabase_client import service_client


def hash_ip(ip: str | None, salt: str) -> str | None:
    if not ip:
        return None
    return hashlib.sha256(f"{salt}:{ip}".encode()).hexdigest()


def write_audit(action: str, entity: str, entity_id: str | None, actor_id: str | None,
                actor_role: str | None, metadata: dict[str, Any] | None = None, ip_hash: str | None = None) -> None:
    service_client().table("audit_logs").insert({
        "action": action,
        "entity": entity,
        "entity_id": entity_id,
        "actor_id": actor_id,
        "actor_role": actor_role,
        "metadata": metadata or {},
        "ip_hash": ip_hash,
    }).execute()
