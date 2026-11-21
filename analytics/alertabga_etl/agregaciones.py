"""Agregaciones (MapReduce sobre DataFrames) por dimensión analítica."""

from functools import reduce

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

DIMENSIONES = ("categoria", "barrio", "comuna", "anio", "anio_mes")


def agregar(df: DataFrame) -> DataFrame:
    """Recibe columnas barrio, comuna, categoria, anio, mes. Devuelve (dimension, clave, conteo)."""
    base = df.withColumn("anio_mes", F.format_string("%04d-%02d", F.col("anio"), F.col("mes")))
    partes = [
        base.groupBy(F.col(dim).cast("string").alias("clave"))
            .agg(F.count(F.lit(1)).alias("conteo"))
            .withColumn("dimension", F.lit(dim))
        for dim in DIMENSIONES
    ]
    return reduce(DataFrame.unionByName, partes).select("dimension", "clave", "conteo")
