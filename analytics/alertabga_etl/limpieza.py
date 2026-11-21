"""Limpieza y normalización de los datasets oficiales.

Las coordenadas de 75fz-q98y vienen con separadores de miles ("7,170,557,382" = 7.170557382),
por eso se reconstruyen a partir de los dígitos: 1 entero para latitud (7.x) y 2 para longitud (-73.x).
Las filas sin coordenadas válidas o fuera del ámbito se excluyen (equivale al 7,4 % del estudio).
"""

import re

from pyspark.sql import Column, DataFrame
from pyspark.sql import functions as F

from . import BBOX

SIN_INFO = "SIN INFORMACION"


def parse_coordenada(raw: str | None, enteros: int) -> float | None:
    """Versión Python de la reconstrucción (documenta y prueba la regla)."""
    if raw is None:
        return None
    digits = re.sub(r"[^0-9]", "", raw)
    if len(digits) <= enteros:
        return None
    value = float(f"{digits[:enteros]}.{digits[enteros:]}")
    return -value if raw.strip().startswith("-") else value


def _coord_expr(col: str, enteros: int) -> Column:
    raw = F.trim(F.col(col))
    digits = F.regexp_replace(raw, "[^0-9]", "")
    value = F.concat(F.substring(digits, 1, enteros), F.lit("."), F.substring(digits, enteros + 1, 64)).cast("double")
    return (F.when(F.length(digits) <= enteros, F.lit(None).cast("double"))
             .when(raw.startswith("-"), -value)
             .otherwise(value))


def _texto(col: str) -> Column:
    t = F.upper(F.trim(F.col(col)))
    return F.when(t.isNull() | (t == ""), F.lit(SIN_INFO)).otherwise(t)


def _numero_inicial(col: str) -> Column:
    """'15. CENTRO' → 15 ; 'SIN INFORMACION' → null."""
    n = F.regexp_extract(F.trim(F.col(col)), r"^(\d+)", 1)
    return F.when(n == "", F.lit(None)).otherwise(n.cast("int"))


def _sin_prefijo(col: str) -> Column:
    """'15. CENTRO' → 'CENTRO'."""
    return F.trim(F.regexp_replace(_texto(col), r"^\d+\.\s*", ""))


def limpiar_historico(df: DataFrame) -> DataFrame:
    lat = _coord_expr("latitud", 1)
    lon = _coord_expr("longitud", 2)
    return (
        df.select(
            _texto("barrios_hecho").alias("barrio"),
            _sin_prefijo("nom_comuna").alias("comuna"),
            _numero_inicial("nom_comuna").alias("num_comuna"),
            _texto("conducta").alias("categoria"),
            _texto("clasificaciones_delito").alias("clasificacion"),
            F.col("ano").cast("int").alias("anio"),
            _numero_inicial("mes").alias("mes"),
            lat.alias("lat"),
            lon.alias("lon"),
        )
        .where(F.col("lat").isNotNull() & F.col("lon").isNotNull())
        .where(F.col("lat").between(BBOX["min_lat"], BBOX["max_lat"]))
        .where(F.col("lon").between(BBOX["min_lon"], BBOX["max_lon"]))
        .where(F.col("anio").isNotNull())
    )


def limpiar_oficial(df: DataFrame) -> DataFrame:
    return df.select(
        _texto("barrios_hecho").alias("barrio"),
        _texto("nom_com").alias("comuna"),
        _numero_inicial("num_com").alias("num_comuna"),
        _texto("delito_solo").alias("categoria"),
        _texto("tipolog_a").alias("tipologia"),
        F.to_date(F.col("fecha_hecho")).alias("fecha"),
        F.col("a_o_num").cast("int").alias("anio"),
        F.col("mes_num").cast("int").alias("mes"),
    ).where(F.col("anio").isNotNull() & F.col("mes").isNotNull())
