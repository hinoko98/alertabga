"""Datos institucionales de referencia (MongoDB): histórico georreferenciado 2010–2021 y agregados oficiales.

Siempre se devuelven con `fuente`, `tipo_fuente` y `periodo` para que la interfaz no los confunda
con reportes ciudadanos recientes (RB-01, RB-03).
"""

import time
from collections import Counter
from enum import Enum

from fastapi import APIRouter, Depends, HTTPException, Query

from ..deps import STAFF_ROLES, CurrentUser, require_roles
from ..mongo import get_db

router = APIRouter(prefix="/historico", tags=["histórico"])

FUENTES = {
    "historico": "datos.gov.co/75fz-q98y",
    "oficial": "datos.gov.co/x46e-abhz",
}


class Dimension(str, Enum):
    categoria = "categoria"
    barrio = "barrio"
    comuna = "comuna"
    anio = "anio"
    anio_mes = "anio_mes"


class Fuente(str, Enum):
    historico = "historico"
    oficial = "oficial"


def _db():
    db = get_db()
    if db is None:
        raise HTTPException(status_code=503, detail="Base histórica no disponible")
    return db


@router.get("/resumen")
def resumen(_: CurrentUser = Depends(require_roles(*STAFF_ROLES))) -> dict:
    db = _db()
    out = []
    for fuente in FUENTES.values():
        meta = db.crime_aggregates.find_one({"fuente": fuente}, {"_id": 0, "tipo_fuente": 1, "periodo": 1, "generado_en": 1})
        if not meta:
            continue
        total = sum(d["conteo"] for d in db.crime_aggregates.find({"fuente": fuente, "dimension": "anio"}, {"conteo": 1}))
        top = list(db.crime_aggregates.find({"fuente": fuente, "dimension": "barrio"}, {"_id": 0, "clave": 1, "conteo": 1})
                   .sort("conteo", -1).limit(10))
        out.append({"fuente": fuente, "tipo_fuente": meta["tipo_fuente"], "periodo": meta["periodo"],
                    "generado_en": meta.get("generado_en"), "total": total, "top_barrios": top})
    return {"fuentes": out,
            "advertencia": "Datos institucionales de referencia; no son reportes ciudadanos de la plataforma."}


@router.get("/agregados")
def agregados(
    fuente: Fuente,
    dimension: Dimension,
    limite: int = Query(default=50, ge=1, le=500),
    _: CurrentUser = Depends(require_roles(*STAFF_ROLES)),
) -> dict:
    db = _db()
    f = FUENTES[fuente.value]
    meta = db.crime_aggregates.find_one({"fuente": f}, {"_id": 0, "tipo_fuente": 1, "periodo": 1}) or {}
    orden = ("clave", 1) if dimension in (Dimension.anio, Dimension.anio_mes) else ("conteo", -1)
    items = list(db.crime_aggregates.find({"fuente": f, "dimension": dimension.value}, {"_id": 0, "clave": 1, "conteo": 1})
                 .sort(*orden).limit(limite))
    return {"fuente": f, "tipo_fuente": meta.get("tipo_fuente"), "periodo": meta.get("periodo"),
            "dimension": dimension.value, "items": items}


_HEAT_CACHE: dict[tuple, tuple[float, dict]] = {}
_HEAT_TTL_S = 3600  # el histórico solo cambia cuando se recarga el ETL


def heat_cells(db, desde: int, hasta: int, categoria: str | None) -> dict:
    """Agrupa las coordenadas del histórico en celdas de ~110 m (3 decimales) para el mapa de calor."""
    key = (id(db), desde, hasta, categoria)
    hit = _HEAT_CACHE.get(key)
    if hit and time.monotonic() - hit[0] < _HEAT_TTL_S:
        return hit[1]
    q: dict = {"anio": {"$gte": desde, "$lte": hasta}}
    if categoria:
        q["categoria"] = categoria
    cells: Counter = Counter()
    for d in db.historical_crimes.find(q, {"_id": 0, "location.coordinates": 1}):
        lon, lat = d["location"]["coordinates"]
        cells[(round(lat, 3), round(lon, 3))] += 1
    out = {"fuente": FUENTES["historico"], "tipo_fuente": "HISTORICO_GEORREFERENCIADO", "periodo": f"{desde}-{hasta}",
           "total": sum(cells.values()), "max": max(cells.values(), default=0),
           "puntos": [[lat, lon, n] for (lat, lon), n in cells.most_common(20_000)],
           "advertencia": "Delitos históricos oficiales; no son reportes ciudadanos de la plataforma."}
    _HEAT_CACHE[key] = (time.monotonic(), out)
    return out


@router.get("/calor")
def calor(
    desde: int = Query(default=2019, ge=2010, le=2021),
    hasta: int = Query(default=2021, ge=2010, le=2021),
    categoria: str | None = Query(default=None, max_length=80),
    _: CurrentUser = Depends(require_roles(*STAFF_ROLES)),
) -> dict:
    if desde > hasta:
        raise HTTPException(status_code=422, detail="El año inicial debe ser menor o igual al final")
    return heat_cells(_db(), desde, hasta, categoria)


@router.get("/categorias")
def categorias(_: CurrentUser = Depends(require_roles(*STAFF_ROLES))) -> list[str]:
    return sorted(c for c in _db().historical_crimes.distinct("categoria") if c)
