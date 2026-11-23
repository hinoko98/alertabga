"""Contratos de entrada/salida de reportes ciudadanos."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

MAX_FUTURE = timedelta(minutes=5)


class ReportIn(BaseModel):
    category_id: UUID
    description: str = Field(min_length=10, max_length=2000)
    additional_info: str | None = Field(default=None, max_length=1000)
    occurred_at: datetime
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0, le=999999)
    location_manual: bool = False
    address_text: str | None = Field(default=None, max_length=200)

    @field_validator("description", "additional_info", "address_text")
    @classmethod
    def _strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @field_validator("description")
    @classmethod
    def _desc_len(cls, v: str | None) -> str:
        if v is None or len(v) < 10:
            raise ValueError("La descripción debe tener al menos 10 caracteres")
        return v

    @field_validator("occurred_at")
    @classmethod
    def _not_future(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError("La fecha debe incluir zona horaria")
        if v > datetime.now(UTC) + MAX_FUTURE:
            raise ValueError("La fecha del hecho no puede ser futura")
        return v


class ReportCreated(BaseModel):
    id: str
    radicado: str
    received_at: str
    status: str
    out_of_scope: bool
    tracking_token: str | None = None


class TrackIn(BaseModel):
    radicado: str = Field(max_length=40)
    token: str = Field(max_length=200)


class TimelineEntry(BaseModel):
    at: str
    kind: str  # "estado" | "mensaje"
    status: str | None = None
    text: str | None = None


class ReportSummary(BaseModel):
    radicado: str
    category: str
    status: str
    received_at: str


class ReportDetail(BaseModel):
    id: str
    radicado: str
    category: str
    status: str
    description: str
    occurred_at: str
    received_at: str
    address_text: str | None
    out_of_scope: bool
    evidence_count: int
    timeline: list[TimelineEntry]


class Category(BaseModel):
    id: str
    name: str
    description: str
    icon: str
    color: str
