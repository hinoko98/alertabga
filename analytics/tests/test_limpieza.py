"""Limpieza de los dos datasets oficiales de datos.gov.co (formatos reales observados)."""

from alertabga_etl.limpieza import limpiar_historico, limpiar_oficial, parse_coordenada

HIST_COLS = ["barrios_hecho", "latitud", "longitud", "nom_comuna", "ano", "mes", "conducta", "clasificaciones_delito"]


def test_parse_coordenada_con_separadores_de_miles():
    assert parse_coordenada("7,170,557,382", enteros=1) == 7.170557382
    assert parse_coordenada("-73,135,108", enteros=2) == -73.135108
    assert parse_coordenada("7.1205", enteros=1) == 7.1205
    assert parse_coordenada("", enteros=1) is None
    assert parse_coordenada(None, enteros=1) is None
    assert parse_coordenada("SIN DATO", enteros=1) is None


def test_limpiar_historico_descarta_coordenadas_invalidas_o_lejanas(spark):
    rows = [
        ("CENTRO", "7,119,8", "-73,125,4", "15. CENTRO", "2015", "03. MARZO", "HURTO A PERSONAS", "HURTOS"),
        ("BUENOS AIRES", "7,170,557,382", "-73,135,108", "14. MORRORICO", "2010", "01. ENERO", "LESIONES PERSONALES", "LESIONES NO FATALES"),
        ("COORD INVERTIDA", "-73,12", "7,11", "15. CENTRO", "2012", "05. MAYO", "HURTO A PERSONAS", "HURTOS"),
        ("BOGOTA", "4,71", "-74,07", "OTRO", "2013", "07. JULIO", "HURTO A PERSONAS", "HURTOS"),
        ("SIN COORD", "", "", "15. CENTRO", "2014", "02. FEBRERO", "HURTO A PERSONAS", "HURTOS"),
    ]
    out = limpiar_historico(spark.createDataFrame(rows, HIST_COLS)).orderBy("barrio").collect()

    assert [r.barrio for r in out] == ["BUENOS AIRES", "CENTRO"]
    centro = out[1]
    assert (centro.anio, centro.mes, centro.comuna, centro.num_comuna) == (2015, 3, "CENTRO", 15)
    assert centro.categoria == "HURTO A PERSONAS"
    assert abs(centro.lat - 7.1198) < 1e-9 and abs(centro.lon + 73.1254) < 1e-9


def test_limpiar_oficial_normaliza_campos(spark):
    rows = [
        ("ciudadela real de minas ", "2026-01-01", "HURTO ENTIDADES COMERCIALES", "DELITOS CONTRA EL PATRIMONIO ECONOMICO", "15", "CENTRO", "2026", "1"),
        ("", "2026-02-10", "HURTO A PERSONAS", "DELITOS CONTRA EL PATRIMONIO ECONOMICO", "SIN INFORMACION", "SIN INFORMACION", "2026", "2"),
    ]
    cols = ["barrios_hecho", "fecha_hecho", "delito_solo", "tipolog_a", "num_com", "nom_com", "a_o_num", "mes_num"]
    out = limpiar_oficial(spark.createDataFrame(rows, cols)).orderBy("mes").collect()

    assert out[0].barrio == "CIUDADELA REAL DE MINAS"
    assert (out[0].anio, out[0].mes, out[0].num_comuna) == (2026, 1, 15)
    assert out[1].barrio == "SIN INFORMACION"
    assert out[1].num_comuna is None
