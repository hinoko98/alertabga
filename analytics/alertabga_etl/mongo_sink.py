"""Escritura a MongoDB con pymongo (sin el conector Spark–Mongo, para no atarse a versiones de Scala)."""

from datetime import UTC, datetime
from typing import Any

from pyspark.sql import DataFrame

LOTE = 1000


def escribir_agregados(db: Any, df: DataFrame, *, fuente: str, tipo_fuente: str, periodo: str) -> int:
    """Reemplaza los agregados de `fuente` (idempotente). Los agregados son pequeños: se recogen en el driver."""
    generado = datetime.now(UTC)
    docs = [
        {**r.asDict(), "fuente": fuente, "tipo_fuente": tipo_fuente, "periodo": periodo, "generado_en": generado}
        for r in df.collect()
    ]
    db.crime_aggregates.delete_many({"fuente": fuente})
    if docs:
        db.crime_aggregates.insert_many(docs)
    return len(docs)


def escribir_registros(db: Any, df: DataFrame, *, fuente: str, periodo: str) -> int:
    """Registros georreferenciados limpios → historical_crimes, con GeoJSON Point [lon, lat]."""
    db.historical_crimes.delete_many({"fuente": fuente})
    total, lote = 0, []
    for r in df.toLocalIterator():
        d = r.asDict()
        d["location"] = {"type": "Point", "coordinates": [d.pop("lon"), d.pop("lat")]}
        d.update(fuente=fuente, periodo=periodo)
        lote.append(d)
        if len(lote) >= LOTE:
            db.historical_crimes.insert_many(lote)
            total, lote = total + len(lote), []
    if lote:
        db.historical_crimes.insert_many(lote)
        total += len(lote)
    return total
