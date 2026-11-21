import mongomock

from alertabga_etl.agregaciones import DIMENSIONES, agregar
from alertabga_etl.mongo_sink import escribir_agregados

COLS = ["barrio", "comuna", "categoria", "anio", "mes"]
ROWS = [
    ("CENTRO", "CENTRO", "HURTO A PERSONAS", 2020, 1),
    ("CENTRO", "CENTRO", "HURTO A PERSONAS", 2020, 1),
    ("CENTRO", "CENTRO", "LESIONES PERSONALES", 2020, 2),
    ("SAN FRANCISCO", "NORTE", "HURTO A PERSONAS", 2021, 5),
    ("SAN FRANCISCO", "NORTE", "HURTO A PERSONAS", 2021, 5),
    ("CABECERA DEL LLANO", "CABECERA", "HURTO A PERSONAS", 2021, 6),
]


def _by(rows, dim):
    return {r["clave"]: r["conteo"] for r in rows if r["dimension"] == dim}


def test_agregar_conteos_por_dimension(spark):
    out = [r.asDict() for r in agregar(spark.createDataFrame(ROWS, COLS)).collect()]
    assert set(r["dimension"] for r in out) == set(DIMENSIONES)
    assert _by(out, "barrio") == {"CENTRO": 3, "SAN FRANCISCO": 2, "CABECERA DEL LLANO": 1}
    assert _by(out, "categoria") == {"HURTO A PERSONAS": 5, "LESIONES PERSONALES": 1}
    assert _by(out, "anio") == {"2020": 3, "2021": 3}
    assert _by(out, "anio_mes") == {"2020-01": 2, "2020-02": 1, "2021-05": 2, "2021-06": 1}


def test_escribir_agregados_reemplaza_por_fuente_y_etiqueta_periodo(spark):
    db = mongomock.MongoClient().alertabga
    db.crime_aggregates.insert_one({"fuente": "datos.gov.co/75fz-q98y", "dimension": "barrio", "clave": "VIEJO", "conteo": 9})
    db.crime_aggregates.insert_one({"fuente": "otra", "dimension": "barrio", "clave": "INTACTO", "conteo": 1})

    df = agregar(spark.createDataFrame(ROWS, COLS))
    n = escribir_agregados(db, df, fuente="datos.gov.co/75fz-q98y", tipo_fuente="HISTORICO_GEORREFERENCIADO",
                           periodo="2010-2021")

    docs = list(db.crime_aggregates.find({"fuente": "datos.gov.co/75fz-q98y"}))
    assert n == len(docs) > 0
    assert all(d["periodo"] == "2010-2021" and d["tipo_fuente"] == "HISTORICO_GEORREFERENCIADO" for d in docs)
    assert not any(d["clave"] == "VIEJO" for d in docs)
    assert db.crime_aggregates.count_documents({"fuente": "otra"}) == 1
