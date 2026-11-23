import re

import pytest

from conftest import CITIZEN_A, citizen_auth

PW = "Clave-Segura-1"


@pytest.fixture
def api(client, citizen_db):
    return client


def register(api, email="nuevo@example.com", password=PW, name="Ana Pérez"):
    return api.post("/api/py/auth/register", json={"email": email, "password": password, "full_name": name})


def test_registro_devuelve_sesion_y_guarda_hash(api, citizen_db):
    r = register(api, email="  Nuevo@Example.com ")
    assert r.status_code == 201
    d = r.json()
    assert d["access_token"] and d["refresh_token"] and d["token_type"] == "bearer"
    doc = citizen_db.citizens.find_one({"email": "nuevo@example.com"})
    assert doc["password_hash"].startswith("scrypt$") and PW not in str(doc)
    me = api.get("/api/py/account", headers={"Authorization": f"Bearer {d['access_token']}"})
    assert me.json()["email"] == "nuevo@example.com" and me.json()["full_name"] == "Ana Pérez"
    # el refresh se guarda como hash, nunca en claro
    assert citizen_db.citizen_sessions.find_one({"_id": d["refresh_token"]}) is None


@pytest.mark.parametrize("kw", [{"email": "malo"}, {"password": "corta"}, {"name": "A"}])
def test_registro_valida(api, kw):
    assert register(api, **kw).status_code == 422


def test_registro_duplicado_mensaje_generico(api):
    r = register(api, email="a@example.com")
    assert r.status_code == 422 and "registrado" not in r.text.lower()


def test_login_ok_y_errores_identicos(api):
    ok = api.post("/api/py/auth/login", json={"email": "A@example.com", "password": PW})
    assert ok.status_code == 200 and ok.json()["access_token"]
    mala = api.post("/api/py/auth/login", json={"email": "a@example.com", "password": "otra-clave-1"})
    nadie = api.post("/api/py/auth/login", json={"email": "nadie@example.com", "password": PW})
    assert mala.status_code == nadie.status_code == 401 and mala.json() == nadie.json()


def test_login_inactivo_401(api, citizen_db):
    citizen_db.citizens.update_one({"_id": CITIZEN_A}, {"$set": {"active": False}})
    assert api.post("/api/py/auth/login", json={"email": "a@example.com", "password": PW}).status_code == 401
    assert api.get("/api/py/account", headers=citizen_auth()).status_code == 401


def test_login_rate_limit(api):
    for _ in range(10):
        api.post("/api/py/auth/login", json={"email": "a@example.com", "password": "x" * 8})
    r = api.post("/api/py/auth/login", json={"email": "a@example.com", "password": PW})
    assert r.status_code == 429


def test_refresh_rota_y_no_se_reutiliza(api):
    s = register(api).json()
    r1 = api.post("/api/py/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r1.status_code == 200 and r1.json()["refresh_token"] != s["refresh_token"]
    assert api.post("/api/py/auth/refresh", json={"refresh_token": s["refresh_token"]}).status_code == 401


def test_logout_invalida_refresh(api):
    s = register(api).json()
    assert api.post("/api/py/auth/logout", json={"refresh_token": s["refresh_token"]}).status_code == 204
    assert api.post("/api/py/auth/refresh", json={"refresh_token": s["refresh_token"]}).status_code == 401


def test_token_alterado_o_vencido_401(api):
    from alertabga.citizens.security import issue_access_token

    vencido = issue_access_token(CITIZEN_A, "secreto-ciudadano-de-prueba-con-32-caracteres", -10)
    assert api.get("/api/py/account", headers={"Authorization": f"Bearer {vencido}"}).status_code == 401
    otro = issue_access_token(CITIZEN_A, "otro-secreto-distinto-de-32-caracteres!!", 900)
    assert api.get("/api/py/account", headers={"Authorization": f"Bearer {otro}"}).status_code == 401


def _code(citizen_db) -> str:
    return re.search(r"\b(\d{6})\b", citizen_db.mailer.sent[-1][2]).group(1)


def test_recuperacion_con_codigo(api, citizen_db):
    r = api.post("/api/py/auth/password/forgot", json={"email": "a@example.com"})
    assert r.status_code == 202
    code = _code(citizen_db)
    sesion_vieja = api.post("/api/py/auth/login", json={"email": "a@example.com", "password": PW}).json()
    ok = api.post("/api/py/auth/password/reset",
                  json={"email": "a@example.com", "code": code, "new_password": "Nueva-Clave-2"})
    assert ok.status_code == 200 and ok.json()["access_token"]
    assert api.post("/api/py/auth/login", json={"email": "a@example.com", "password": "Nueva-Clave-2"}).status_code == 200
    # el cambio cierra las demás sesiones y el código no se reutiliza
    assert api.post("/api/py/auth/refresh", json={"refresh_token": sesion_vieja["refresh_token"]}).status_code == 401
    again = api.post("/api/py/auth/password/reset",
                     json={"email": "a@example.com", "code": code, "new_password": "Otra-Clave-3"})
    assert again.status_code == 400


def test_recuperacion_no_revela_correos(api, citizen_db):
    a = api.post("/api/py/auth/password/forgot", json={"email": "a@example.com"})
    b = api.post("/api/py/auth/password/forgot", json={"email": "nadie@example.com"})
    assert a.status_code == b.status_code == 202 and a.json() == b.json()
    assert len(citizen_db.mailer.sent) == 1


def test_recuperacion_bloquea_tras_5_intentos(api, citizen_db):
    api.post("/api/py/auth/password/forgot", json={"email": "a@example.com"})
    code = _code(citizen_db)
    for _ in range(5):
        api.post("/api/py/auth/password/reset", json={"email": "a@example.com", "code": "000000"
                 if code != "000000" else "111111", "new_password": "Nueva-Clave-2"})
    r = api.post("/api/py/auth/password/reset", json={"email": "a@example.com", "code": code,
                                                      "new_password": "Nueva-Clave-2"})
    assert r.status_code == 400


def test_perfil_actualiza_solo_campos_permitidos(api, citizen_db):
    r = api.patch("/api/py/account", headers=citizen_auth(),
                  json={"full_name": "Nombre Nuevo", "phone": "+57 300 123 4567", "notify_status_changes": True})
    assert r.status_code == 200 and r.json()["phone"] == "+57 300 123 4567"
    bad = api.patch("/api/py/account", headers=citizen_auth(), json={"phone": "abc"})
    assert bad.status_code == 422
    api.patch("/api/py/account", headers=citizen_auth(), json={"active": False, "email": "x@x.co"})
    doc = citizen_db.citizens.find_one({"_id": CITIZEN_A})
    assert doc["active"] is True and doc["email"] == "a@example.com"


def test_cambiar_contrasena(api):
    bad = api.post("/api/py/account/password", headers=citizen_auth(),
                   json={"current_password": "incorrecta-1", "new_password": "Nueva-Clave-2"})
    assert bad.status_code == 400
    ok = api.post("/api/py/account/password", headers=citizen_auth(),
                  json={"current_password": PW, "new_password": "Nueva-Clave-2"})
    assert ok.status_code == 204
