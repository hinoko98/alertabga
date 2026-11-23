import hashlib
from datetime import UTC, datetime, timedelta

import pytest

from conftest import CITIZEN_A as USER_A
from conftest import CITIZEN_B as USER_B
from conftest import citizen_auth, make_token
from fakes import CAT_ID, CAT_INACTIVA, FakeRepository


@pytest.fixture
def repo():
    return FakeRepository()


@pytest.fixture
def api(client, repo, citizen_db):
    from alertabga.reports import get_report_service
    from alertabga.reports.service import ReportService

    client.app.dependency_overrides[get_report_service] = lambda: ReportService(repo, "sal")
    return client


def auth(user=USER_A):
    return citizen_auth(user)


def body(**kw):
    b = {"category_id": CAT_ID, "description": "Me robaron el celular en la esquina",
         "occurred_at": (datetime.now(UTC) - timedelta(hours=1)).isoformat(),
         "lat": 7.119, "lon": -73.122, "accuracy_m": 12.5}
    b.update(kw)
    return b


def anon(api, **kw):
    return api.post("/api/py/reports/anonymous", json=body(**kw), headers={"X-Device-Id": "dev-1"})


# ------------------------------------------------------------ creación
def test_anonimo_devuelve_token_y_guarda_solo_hash(api, repo):
    r = anon(api)
    assert r.status_code == 201
    data = r.json()
    token = data["tracking_token"]
    assert len(token) >= 43 and data["radicado"].startswith("BGA-")
    inc = repo.incidents[data["id"]]
    assert inc["source"] == "APP_ANONIMO" and inc["reporter_id"] is None
    assert inc["anon_token_hash"] == hashlib.sha256(token.encode()).hexdigest()
    assert token not in str(inc) and token not in str(repo.audits)
    assert (inc["lat"], inc["lon"]) == (7.119, -73.122) and inc["out_of_scope"] is False


def test_autenticado_sin_token_de_seguimiento(api, repo):
    r = api.post("/api/py/reports", json=body(), headers=auth())
    assert r.status_code == 201
    assert "tracking_token" not in r.json()
    inc = repo.incidents[r.json()["id"]]
    assert inc["source"] == "APP_AUTENTICADO" and inc["reporter_id"] == USER_A and inc["anon_token_hash"] is None
    assert repo.audits[-1]["action"] == "REPORTE_CREADO"


def test_reporte_autenticado_exige_token(api):
    assert api.post("/api/py/reports", json=body()).status_code == 401


def test_token_de_supabase_no_sirve_en_la_app(api):
    # Los JWT de Supabase (personal del panel) no son sesiones ciudadanas.
    r = api.post("/api/py/reports", json=body(), headers={"Authorization": f"Bearer {make_token(USER_A)}"})
    assert r.status_code == 401


def test_ciudadano_inexistente_401(api):
    r = api.post("/api/py/reports", json=body(), headers=auth("33333333-3333-3333-3333-333333333333"))
    assert r.status_code == 401


def test_fuera_de_ambito_se_marca(api, repo):
    r = anon(api, lat=4.71, lon=-74.07)
    assert r.status_code == 201 and r.json()["out_of_scope"] is True
    assert repo.incidents[r.json()["id"]]["out_of_scope"] is True


def test_sexto_reporte_429(api):
    for _ in range(5):
        assert anon(api).status_code == 201
    assert anon(api).status_code == 429


def test_rate_limit_separa_dispositivos(api):
    for _ in range(5):
        anon(api)
    r = api.post("/api/py/reports/anonymous", json=body(), headers={"X-Device-Id": "dev-2"})
    assert r.status_code == 201


def test_categoria_inactiva_422(api):
    assert anon(api, category_id=CAT_INACTIVA).status_code == 422


@pytest.mark.parametrize("campo", [
    {"occurred_at": (datetime.now(UTC) + timedelta(hours=1)).isoformat()},
    {"occurred_at": "2026-01-01T10:00:00"},  # sin zona horaria
    {"description": "corto"},
    {"description": "          espacios        "},
    {"description": "x" * 2001},
    {"lat": 91},
    {"lon": -181},
    {"accuracy_m": -1},
])
def test_validaciones_422(api, campo):
    assert anon(api, **campo).status_code == 422


# ------------------------------------------------------------ seguimiento anónimo
def test_track_ok_con_timeline(api, repo):
    data = anon(api).json()
    r = api.post("/api/py/reports/track", json={"radicado": data["radicado"], "token": data["tracking_token"]})
    assert r.status_code == 200
    d = r.json()
    assert d["status"] == "RECIBIDO" and d["category"] == "Hurto"
    assert d["timeline"][0] == {"at": d["timeline"][0]["at"], "kind": "estado", "status": "RECIBIDO",
                                "text": "Reporte recibido"}


def test_track_token_erroneo_y_radicado_inexistente_mismo_404(api):
    data = anon(api).json()
    malo = api.post("/api/py/reports/track", json={"radicado": data["radicado"], "token": "x" * 43})
    inexistente = api.post("/api/py/reports/track", json={"radicado": "BGA-2026-999999",
                                                          "token": data["tracking_token"]})
    formato = api.post("/api/py/reports/track", json={"radicado": "cualquier-cosa", "token": "x"})
    assert malo.status_code == inexistente.status_code == formato.status_code == 404
    assert malo.json() == inexistente.json() == formato.json() == {"detail": "Radicado o código no válido"}


def test_track_de_reporte_autenticado_404(api):
    data = api.post("/api/py/reports", json=body(), headers=auth()).json()
    r = api.post("/api/py/reports/track", json={"radicado": data["radicado"], "token": ""})
    assert r.status_code == 404


def test_timeline_excluye_internos(api, repo):
    data = anon(api).json()
    repo.history += [
        {"incident_id": data["id"], "action": "NOTA_INTERNA", "new_status": None, "note": "SECRETO-1",
         "is_internal": True, "created_at": "2026-11-22T10:00:00+00:00"},
        {"incident_id": data["id"], "action": "ASIGNACION", "new_status": None, "note": "SECRETO-2",
         "is_internal": True, "created_at": "2026-11-22T10:01:00+00:00"},
        {"incident_id": data["id"], "action": "MENSAJE_CIUDADANO", "new_status": None,
         "note": "Una patrulla verificó el sector", "is_internal": False, "created_at": "2026-11-22T10:02:00+00:00"},
    ]
    r = api.post("/api/py/reports/track", json={"radicado": data["radicado"], "token": data["tracking_token"]})
    assert "SECRETO" not in r.text
    assert r.json()["timeline"][-1] == {"at": "2026-11-22T10:02:00+00:00", "kind": "mensaje", "status": None,
                                        "text": "Una patrulla verificó el sector"}


def test_track_rate_limit(api):
    for _ in range(20):
        api.post("/api/py/reports/track", json={"radicado": "BGA-2026-000001", "token": "x"})
    r = api.post("/api/py/reports/track", json={"radicado": "BGA-2026-000001", "token": "x"})
    assert r.status_code == 429


# ------------------------------------------------------------ lecturas autenticadas
def test_mine_y_detalle_propio(api):
    rad = api.post("/api/py/reports", json=body(), headers=auth()).json()["radicado"]
    mine = api.get("/api/py/reports/mine", headers=auth())
    assert [m["radicado"] for m in mine.json()] == [rad]
    d = api.get(f"/api/py/reports/{rad}", headers=auth())
    assert d.status_code == 200 and d.json()["radicado"] == rad


def test_no_ve_radicado_ajeno(api):
    rad = api.post("/api/py/reports", json=body(), headers=auth(USER_A)).json()["radicado"]
    assert api.get("/api/py/reports/mine", headers=auth(USER_B)).json() == []
    r = api.get(f"/api/py/reports/{rad}", headers=auth(USER_B))
    assert r.status_code == 404 and r.json() == {"detail": "Radicado o código no válido"}


def test_categorias_publicas(api):
    r = api.get("/api/py/categories")
    assert r.status_code == 200 and [c["name"] for c in r.json()] == ["Hurto"]
