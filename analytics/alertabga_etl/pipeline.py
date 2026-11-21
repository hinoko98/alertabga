"""Pipeline completo: descarga oficial (SODA API) → Spark → MongoDB.

Uso:
    python -m alertabga_etl.pipeline --mongo-uri mongodb://127.0.0.1:27018 [--db alertabga] [--solo historico|oficial]
"""

import argparse
import os
import sys
from pathlib import Path

import requests
from pymongo import ASCENDING, GEOSPHERE, MongoClient
from pyspark.sql import SparkSession

from . import FUENTE_HISTORICO, FUENTE_OFICIAL
from .agregaciones import agregar
from .limpieza import limpiar_historico, limpiar_oficial
from .mongo_sink import escribir_agregados, escribir_registros

RAW_DIR = Path(__file__).resolve().parents[2] / "data" / "raw"
SODA = "https://www.datos.gov.co/resource/{id}.csv?$limit=1000000"


def descargar(dataset_id: str) -> Path:
    """Descarga el CSV con nombres de campo (fieldName). Se reutiliza si ya existe."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    destino = RAW_DIR / f"{dataset_id}.csv"
    if destino.exists() and destino.stat().st_size > 0:
        return destino
    with requests.get(SODA.format(id=dataset_id), stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(destino, "wb") as fh:
            for chunk in r.iter_content(1 << 20):
                fh.write(chunk)
    return destino


def _spark() -> SparkSession:
    os.environ.setdefault("PYSPARK_PYTHON", sys.executable)
    return (SparkSession.builder.master("local[*]").appName("alertabga-etl")
            .config("spark.sql.shuffle.partitions", "8").config("spark.ui.enabled", "false").getOrCreate())


def _leer_csv(spark: SparkSession, path: Path):
    return spark.read.option("header", True).option("multiLine", True).option("escape", '"').csv(str(path))


def correr_historico(spark: SparkSession, db) -> dict:
    crudo = _leer_csv(spark, descargar("75fz-q98y"))
    total = crudo.count()
    limpio = limpiar_historico(crudo).cache()
    validos = limpio.count()
    periodo = "2010-2021"
    n_reg = escribir_registros(db, limpio, fuente=FUENTE_HISTORICO, periodo=periodo)
    n_agg = escribir_agregados(db, agregar(limpio), fuente=FUENTE_HISTORICO,
                               tipo_fuente="HISTORICO_GEORREFERENCIADO", periodo=periodo)
    db.historical_crimes.create_index([("location", GEOSPHERE)])
    db.historical_crimes.create_index([("anio", ASCENDING), ("barrio", ASCENDING)])
    return {"fuente": FUENTE_HISTORICO, "crudos": total, "validos": validos,
            "pct_validos": round(100 * validos / total, 2) if total else 0, "registros": n_reg, "agregados": n_agg}


def correr_oficial(spark: SparkSession, db) -> dict:
    crudo = _leer_csv(spark, descargar("x46e-abhz"))
    limpio = limpiar_oficial(crudo).cache()
    rango = limpio.agg({"fecha": "min"}).first()[0], limpio.agg({"fecha": "max"}).first()[0]
    periodo = f"{rango[0]:%Y-%m}..{rango[1]:%Y-%m}"
    n_agg = escribir_agregados(db, agregar(limpio), fuente=FUENTE_OFICIAL,
                               tipo_fuente="OFICIAL_AGREGADO", periodo=periodo)
    db.crime_aggregates.create_index([("fuente", ASCENDING), ("dimension", ASCENDING), ("conteo", -1)])
    return {"fuente": FUENTE_OFICIAL, "registros": limpio.count(), "periodo": periodo, "agregados": n_agg}


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description="ETL AlertaBGA → MongoDB")
    ap.add_argument("--mongo-uri", default=os.environ.get("MONGODB_URI", "mongodb://127.0.0.1:27018"))
    ap.add_argument("--db", default=os.environ.get("MONGODB_DB", "alertabga"))
    ap.add_argument("--solo", choices=["historico", "oficial"])
    args = ap.parse_args(argv)

    db = MongoClient(args.mongo_uri)[args.db]
    spark = _spark()
    try:
        if args.solo in (None, "historico"):
            print(correr_historico(spark, db))
        if args.solo in (None, "oficial"):
            print(correr_oficial(spark, db))
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
