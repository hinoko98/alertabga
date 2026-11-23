import mongomock
import pytest

from conftest import make_token

USER_ID = "11111111-1111-1111-1111-111111111111"


def _seed(db):
    base = {"fuente": "datos.gov.co/75fz-q98y", "tipo_fuente": "HISTORICO_GEORREFERENCIADO", "periodo": "2010-2021"}
    db.crime_aggregates.insert_many([
        {**base, "dimension": "barrio", "clave": "CENTRO", "conteo": 11199},
        {**base, "dimension": "barrio", "clave": "SAN FRANCISCO", "conteo": 5944},
        {**base, "dimension": "anio", "clave": "2010", "conteo": 100},
        {**base, "dimension": "anio", "clave": "2011", "conteo": 50},
        {"fuente": "datos.gov.co/x46e-abhz", "tipo_fuente": "OFICIAL_AGREGADO", "periodo": "2016-01..2026-09",
         "dimension": "anio", "clave": "2026", "conteo": 12735},
    ])


@pytest.fixture
def mongo(monkeypatch):
    from alertabga.routers import historico

    db = mongomock.MongoClient().alertabga
    _seed(db)
    monkeypatch.setattr(historico, "get_db", lambda: db)
    return db


def _as(monkeypatch, role):
    from alertabga import deps

    monkeypatch.setattr(deps, "fetch_profile",
                        lambda t, u: {"id": USER_ID, "role_code": role, "full_name": None, "active": True})
    return {"Authorization": f"Bearer {make_token()}"}


def test_resumen_sin_token_401(client, mongo):
    assert client.get("/api/py/historico/resumen").status_code == 401


def test_resumen_ciudadano_403(client, mongo, monkeypatch):
    assert client.get("/api/py/historico/resumen", headers=_as(monkeypatch, "ciudadano")).status_code == 403


def test_resumen_etiqueta_periodo_y_fuente(client, mongo, monkeypatch):
    r = client.get("/api/py/historico/resumen", headers=_as(monkeypatch, "operador"))
    assert r.status_code == 200
    fuentes = {f["tipo_fuente"]: f for f in r.json()["fuentes"]}
    hist = fuentes["HISTORICO_GEORREFERENCIADO"]
    assert hist["periodo"] == "2010-2021"
    assert hist["fuente"] == "datos.gov.co/75fz-q98y"
    assert hist["total"] == 150
    assert [b["clave"] for b in hist["top_barrios"]] == ["CENTRO", "SAN FRANCISCO"]
    assert fuentes["OFICIAL_AGREGADO"]["periodo"] == "2016-01..2026-09"


def test_agregados_dimension_invalida_422(client, mongo, monkeypatch):
    r = client.get("/api/py/historico/agregados?fuente=historico&dimension=cedula", headers=_as(monkeypatch, "supervisor"))
    assert r.status_code == 422


def test_agregados_ordenados_desc(client, mongo, monkeypatch):
    r = client.get("/api/py/historico/agregados?fuente=historico&dimension=barrio&limite=1",
                   headers=_as(monkeypatch, "supervisor"))
    assert r.status_code == 200
    body = r.json()
    assert body["periodo"] == "2010-2021"
    assert body["items"] == [{"clave": "CENTRO", "conteo": 11199}]


def test_mongo_no_configurado_503(client, monkeypatch):
    from alertabga.routers import historico

    monkeypatch.setattr(historico, "get_db", lambda: None)
    r = client.get("/api/py/historico/resumen", headers=_as(monkeypatch, "operador"))
    assert r.status_code == 503


def test_calor_agrupa_en_celdas_y_etiqueta_fuente(client, mongo, monkeypatch):
    from alertabga.routers import historico

    historico._HEAT_CACHE.clear()
    mongo.historical_crimes.insert_many([
        {"categoria": "HURTO", "anio": 2020, "location": {"type": "Point", "coordinates": [-73.12341, 7.11112]}},
        {"categoria": "HURTO", "anio": 2021, "location": {"type": "Point", "coordinates": [-73.12339, 7.11108]}},
        {"categoria": "RIÑAS", "anio": 2020, "location": {"type": "Point", "coordinates": [-73.13, 7.12]}},
        {"categoria": "HURTO", "anio": 2012, "location": {"type": "Point", "coordinates": [-73.14, 7.13]}},
    ])
    r = client.get("/api/py/historico/calor?desde=2019&hasta=2021", headers=_as(monkeypatch, "operador"))
    assert r.status_code == 200
    body = r.json()
    assert body["tipo_fuente"] == "HISTORICO_GEORREFERENCIADO" and body["periodo"] == "2019-2021"
    assert body["total"] == 3 and body["max"] == 2
    assert body["puntos"][0] == [7.111, -73.123, 2]
    solo = client.get("/api/py/historico/calor?desde=2010&hasta=2021&categoria=RI%C3%91AS",
                      headers=_as(monkeypatch, "operador")).json()
    assert solo["total"] == 1


def test_calor_rango_invertido_422(client, mongo, monkeypatch):
    r = client.get("/api/py/historico/calor?desde=2021&hasta=2015", headers=_as(monkeypatch, "operador"))
    assert r.status_code == 422
