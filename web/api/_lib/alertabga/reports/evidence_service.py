"""Evidencias fotográficas: el teléfono sube directo al almacenamiento con una URL PUT firmada y la API
confirma con HEAD que el objeto coincide con lo declarado. El binario nunca pasa por Vercel."""

import uuid
from datetime import UTC, datetime
from typing import Protocol

from .. import storage as default_storage
from .service import ReportService, Requester

MAX_FILES = 3
ACTIVE = ("PENDIENTE", "CONFIRMADA")


class Storage(Protocol):
    def extension_for(self, mime: str) -> str: ...
    def validate(self, mime: str, size: int) -> None: ...
    def presign_put(self, key: str, mime: str, size: int) -> str: ...
    def head(self, key: str) -> dict | None: ...
    def delete(self, key: str) -> None: ...


class TooManyFiles(Exception):
    pass


class InvalidFile(Exception):
    pass


class NotUploaded(Exception):
    pass


class EvidenceNotFound(Exception):
    pass


class EvidenceService:
    def __init__(self, reports: ReportService, storage: Storage = default_storage) -> None:  # type: ignore[assignment]
        self.reports = reports
        self.repo = reports.repo
        self.storage = storage

    def presign(self, radicado: str, mime: str, size: int, req: Requester,
                tracking_token: str | None = None) -> dict:
        inc = self.reports.resolve(radicado, req, tracking_token)  # NotFound si no es suyo
        try:
            self.storage.validate(mime, size)
        except ValueError as e:
            raise InvalidFile(str(e)) from e
        if self.repo.count_evidence(inc["id"], ACTIVE) >= MAX_FILES:
            raise TooManyFiles()

        evidence_id = str(uuid.uuid4())
        key = f"incidents/{inc['id']}/{evidence_id}.{self.storage.extension_for(mime)}"
        url = self.storage.presign_put(key, mime, size)
        self.repo.insert_evidence({
            "id": evidence_id, "incident_id": inc["id"], "storage_key": key, "mime_type": mime,
            "size_bytes": size, "uploaded_by": req.user_id if tracking_token is None else None,
        })
        return {"evidence_id": evidence_id, "upload_url": url, "method": "PUT",
                "headers": {"Content-Type": mime}}

    def confirm(self, evidence_id: str, radicado: str, req: Requester, tracking_token: str | None = None) -> str:
        inc = self.reports.resolve(radicado, req, tracking_token)
        try:
            uuid.UUID(evidence_id)
        except ValueError as e:
            raise EvidenceNotFound() from e
        ev = self.repo.find_evidence(evidence_id, inc["id"])
        if ev is None:
            raise EvidenceNotFound()
        if ev["status"] != "PENDIENTE":
            return ev["status"]

        obj = self.storage.head(ev["storage_key"])
        if obj is None:
            raise NotUploaded()
        if obj["size"] != ev["size_bytes"] or obj["mime"] != ev["mime_type"]:
            self.storage.delete(ev["storage_key"])
            self.repo.update_evidence(evidence_id, {"status": "RECHAZADA"})
            return "RECHAZADA"

        self.repo.update_evidence(evidence_id, {"status": "CONFIRMADA", "confirmed_at": datetime.now(UTC).isoformat()})
        self.repo.audit("EVIDENCIA_SUBIDA", "evidence", evidence_id, req.user_id if tracking_token is None else None,
                        req.role if tracking_token is None and req.user_id else "anonimo",
                        {"incident_id": inc["id"], "radicado": inc["radicado"], "size": ev["size_bytes"],
                         "mime": ev["mime_type"]},
                        self.reports._ip_hash(req))
        return "CONFIRMADA"
