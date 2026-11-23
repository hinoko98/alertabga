"""Reglas de reportes ciudadanos: creación (autenticada/anónima), rate limit, seguimiento sin enumeración."""

import hashlib
import hmac
import re
import secrets
from dataclasses import dataclass

from .repository import ReportRepository
from .schemas import ReportDetail, ReportIn, ReportSummary, TimelineEntry

RADICADO_RE = re.compile(r"^BGA-\d{4}-\d{6,}$")
TRACK_MAX, TRACK_WINDOW_MIN = 20, 10
# Hash de relleno: la comparación de un radicado inexistente cuesta lo mismo que la de uno real.
_DUMMY_HASH = hashlib.sha256(b"alertabga-dummy").hexdigest()


class NotFound(Exception):
    """Radicado inexistente, ajeno o token inválido (indistinguibles para el cliente)."""


class RateLimited(Exception):
    pass


class InvalidReport(Exception):
    pass


@dataclass(frozen=True)
class Requester:
    """Quién hace la solicitud. `user_id` para ciudadanos autenticados; si no, anónimo."""
    ip: str | None
    device_id: str | None
    user_id: str | None = None
    role: str | None = None
    token: str | None = None


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def rate_key(req: Requester, salt: str, scope: str = "report") -> str:
    if req.user_id:
        return f"{scope}:user:{req.user_id}"
    raw = f"{salt}|{req.ip or ''}|{req.device_id or ''}"
    return f"{scope}:anon:{hashlib.sha256(raw.encode()).hexdigest()}"


class ReportService:
    def __init__(self, repo: ReportRepository, salt: str) -> None:
        self.repo = repo
        self.salt = salt

    # ------------------------------------------------------------ creación
    def create(self, data: ReportIn, req: Requester) -> dict:
        category = self.repo.active_category(str(data.category_id))
        if category is None:
            raise InvalidReport("Categoría no válida")

        cfg = self.repo.rate_limit_setting()
        if not self.repo.hit_rate_limit(rate_key(req, self.salt), int(cfg.get("max", 5)),
                                        int(cfg.get("window_minutes", 60))):
            raise RateLimited()

        anonymous = req.user_id is None
        token = secrets.token_urlsafe(32) if anonymous else None
        row = {
            "category_id": str(data.category_id),
            "description": data.description,
            "additional_info": data.additional_info,
            "occurred_at": data.occurred_at.isoformat(),
            "location": f"SRID=4326;POINT({data.lon} {data.lat})",
            "accuracy_m": data.accuracy_m,
            "location_manual": data.location_manual,
            "address_text": data.address_text,
            "source": "APP_ANONIMO" if anonymous else "APP_AUTENTICADO",
            "reporter_id": req.user_id,
            "anon_token_hash": hash_token(token) if token else None,
        }
        created = self.repo.insert_incident(row)
        self.repo.audit("REPORTE_CREADO", "incidents", created["id"], req.user_id,
                        req.role if req.user_id else "anonimo",
                        {"radicado": created["radicado"], "category": category["name"],
                         "out_of_scope": created["out_of_scope"]},
                        self._ip_hash(req))
        return {**created, "tracking_token": token}

    # ------------------------------------------------------------ resolución autorizada de un incidente
    def resolve(self, radicado: str, req: Requester, tracking_token: str | None = None) -> dict:
        """Devuelve el incidente solo si el solicitante es su dueño (autenticado) o tiene el token (anónimo).
        Cualquier otro caso → NotFound, sin distinguir la causa."""
        radicado = (radicado or "").strip().upper()
        inc = self.repo.find_by_radicado(radicado) if RADICADO_RE.match(radicado) else None

        if req.user_id and tracking_token is None:
            if inc is None or inc.get("reporter_id") != req.user_id:
                raise NotFound()
            return inc

        stored = (inc or {}).get("anon_token_hash") or _DUMMY_HASH
        ok = hmac.compare_digest(hash_token(tracking_token or ""), stored)
        if inc is None or inc.get("source") != "APP_ANONIMO" or not tracking_token or not ok:
            raise NotFound()
        return inc

    # ------------------------------------------------------------ lecturas
    def track(self, radicado: str, token: str, req: Requester) -> ReportDetail:
        if not self.repo.hit_rate_limit(rate_key(Requester(req.ip, None), self.salt, "track"),
                                        TRACK_MAX, TRACK_WINDOW_MIN):
            raise RateLimited()
        return self._detail(self.resolve(radicado, Requester(req.ip, req.device_id), token))

    def detail_for_owner(self, radicado: str, req: Requester) -> ReportDetail:
        return self._detail(self.resolve(radicado, req))

    def mine(self, req: Requester) -> list[ReportSummary]:
        assert req.user_id and req.token
        return [ReportSummary(radicado=r["radicado"], category=r["category"], status=r["status"],
                              received_at=r["received_at"]) for r in self.repo.list_mine(req.token, req.user_id)]

    def _detail(self, inc: dict) -> ReportDetail:
        return ReportDetail(
            id=inc["id"],
            radicado=inc["radicado"],
            category=inc["category"],
            status=inc["status"],
            description=inc["description"],
            occurred_at=inc["occurred_at"],
            received_at=inc["received_at"],
            address_text=inc.get("address_text"),
            out_of_scope=bool(inc.get("out_of_scope")),
            evidence_count=self.repo.count_evidence(inc["id"], ("CONFIRMADA",)),
            timeline=[_entry(h) for h in self.repo.public_timeline(inc["id"])],
        )

    def _ip_hash(self, req: Requester) -> str | None:
        from ..audit import hash_ip

        return hash_ip(req.ip, self.salt)


def _entry(h: dict) -> TimelineEntry:
    if h["action"] == "MENSAJE_CIUDADANO":
        return TimelineEntry(at=h["created_at"], kind="mensaje", text=h.get("note"))
    text = "Reporte recibido" if h["action"] == "CREADO" else h.get("note")
    return TimelineEntry(at=h["created_at"], kind="estado", status=h.get("new_status"), text=text)
