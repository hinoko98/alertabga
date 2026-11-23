"""Panel institucional: bandeja, detalle, gestión de estados, permisos, resúmenes y exportación."""

import csv
import io
import uuid
from datetime import UTC, datetime, timedelta

import mongomock
import pytest

from conftest import make_token

ADMIN = "aaaaaaaa-0000-0000-0000-000000000001"
SUPER = "aaaaaaaa-0000-0000-0000-000000000002"
OP_A = "aaaaaaaa-0000-0000-0000-000000000003"
OP_B = "aaaaaaaa-0000-0000-0000-000000000004"
CITIZEN = "cccccccc-0000-0000-0000-000000000001"

STAFF = {
    ADMIN: {"id": ADMIN, "full_name": "Ana Admin", "role_code": "administrador", "active": True},
    SUPER: {"id": SUPER, "full_name": "Sergio Supervisor", "role_code": "supervisor", "active": True},
    OP_A: {"id": OP_A, "full_name": "Olga Operadora", "role_code": "operador", "active": True},
    OP_B: {"id": OP_B, "full_name": "Oscar Operador", "role_code": "operador", "active": True},
}


class FakeDirectory:
    def staff(self):
        return [{"id": s["id"], "full_name": s["full_name"], "role": s["role_code"], "active": s["active"]}
                for s in STAFF.values()]

    def get(self, staff_id):
        return next((s for s in self.staff() if s["id"] == staff_id), None)


class FakeStorage:
    def presign_get(self, key, ttl=300, host=None):
        return f"http://s3.test/{key}?firma=1"


def _incident(db, n, *, status="RECIBIDO", days_ago=0, category="Hurto", reporter=None, assigned=None, **extra):
    now = datetime.now(UTC) - timedelta(days=days_ago)
    iid = str(uuid.uuid4())
    db.incidents.insert_one({
        "_id": iid, "radicado": f"BGA-2026-{n:06d}", "category_id": f"cat-{category}", "category_name": category,
        "description": f"Descripción del caso {n}", "occurred_at": now - timedelta(hours=1), "received_at": now,
        "location": {"type": "Point", "coordinates": [-73.12 - n / 1000, 7.11 + n / 1000]}, "accuracy_m": 10,
        "status": status, "priority": "MEDIA", "verification_level": "REPORTE_CIUDADANO",
        "source": "APP_AUTENTICADO" if reporter else "APP_ANONIMO", "reporter_id": reporter,
        "anon_token_hash": None if reporter else "hash", "assigned_to": assigned,
        "assigned_name": STAFF[assigned]["full_name"] if assigned else None,
        "out_of_scope": False, "updated_at": now, **extra,
    })
    db.incident_history.insert_one({"incident_id": iid, "actor_id": reporter, "action": "CREADO", "old_status": None,
                                    "new_status": "RECIBIDO", "note": "Reporte recibido", "is_internal": False,
                                    "created_at": now, "seq": 0})
    return iid


@pytest.fixture
def db():
    d = mongomock.MongoClient().alertabga
    d.citizens.insert_one({"_id": CITIZEN, "email": "laura@example.com", "full_name": "Laura Ciudadana",
                           "phone": "3001234567", "active": True})
    _incident(d, 1, reporter=CITIZEN)
    _incident(d, 2, status="ASIGNADO", assigned=OP_A, category="Riñas")
    _incident(d, 3, status="EN_ATENCION", assigned=OP_B, days_ago=2)
    _incident(d, 4, status="CERRADO", days_ago=5, category="Riñas", first_response_at=datetime.now(UTC),
              closed_at=datetime.now(UTC))
    _incident(d, 5, days_ago=40)
    d.evidence.insert_one({"_id": "ev-1", "incident_id": d.incidents.find_one({"radicado": "BGA-2026-000001"})["_id"],
                           "storage_key": "incidents/x/ev-1.jpg", "mime_type": "image/jpeg", "size_bytes": 10,
                           "status": "CONFIRMADA", "created_at": datetime.now(UTC)})
    return d


@pytest.fixture
def api(client, db, monkeypatch):
    from alertabga import deps
    from alertabga.panel import get_panel_service
    from alertabga.panel.service import PanelService

    monkeypatch.setattr(deps, "fetch_profile", lambda token, uid: STAFF.get(uid) or
                        {"id": uid, "role_code": "ciudadano", "full_name": None, "active": True})
    client.app.dependency_overrides[get_panel_service] = lambda: PanelService(db, FakeDirectory(), FakeStorage())
    yield client
    client.app.dependency_overrides.clear()


def as_(uid):
    return {"Authorization": f"Bearer {make_token(uid)}"}


def hist(db, radicado):
    iid = db.incidents.find_one({"radicado": radicado})["_id"]
    return list(db.incident_history.find({"incident_id": iid}).sort([("created_at", 1), ("seq", 1)]))


# ------------------------------------------------------------------ acceso
def test_sin_token_401(api):
    assert api.get("/api/py/staff/incidents").status_code == 401


def test_ciudadano_de_supabase_403(api):
    assert api.get("/api/py/staff/incidents", headers=as_(CITIZEN)).status_code == 403


# ------------------------------------------------------------------ bandeja
def test_bandeja_lista_ordenada_y_paginada(api):
    r = api.get("/api/py/staff/incidents?page_size=2", headers=as_(OP_A))
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 5
    assert [i["radicado"] for i in body["items"]] == ["BGA-2026-000002", "BGA-2026-000001"]
    assert "anon_token_hash" not in body["items"][0]


@pytest.mark.parametrize("query,expected", [
    ("status=RECIBIDO", {"BGA-2026-000001", "BGA-2026-000005"}),
    ("status=ASIGNADO,EN_ATENCION", {"BGA-2026-000002", "BGA-2026-000003"}),
    ("category_id=cat-Riñas", {"BGA-2026-000002", "BGA-2026-000004"}),
    ("assigned=none&status=RECIBIDO", {"BGA-2026-000001", "BGA-2026-000005"}),
    ("assigned=me", {"BGA-2026-000002"}),
    ("q=000003", {"BGA-2026-000003"}),
    ("q=caso 4", {"BGA-2026-000004"}),
    ("q=.*", set()),
])
def test_filtros_de_bandeja(api, query, expected):
    r = api.get(f"/api/py/staff/incidents?{query}&page_size=50", headers=as_(OP_A))
    assert {i["radicado"] for i in r.json()["items"]} == expected


def test_estado_invalido_422(api):
    assert api.get("/api/py/staff/incidents?status=INVENTADO", headers=as_(OP_A)).status_code == 422


# ------------------------------------------------------------------ detalle
def test_detalle_completo_para_el_personal(api, db):
    r = api.get("/api/py/staff/incidents/BGA-2026-000001", headers=as_(OP_A))
    assert r.status_code == 200
    d = r.json()
    assert d["reporter"] == {"type": "CUENTA", "full_name": "Laura Ciudadana", "email": "laura@example.com",
                             "phone": "3001234567"}
    assert d["evidence"][0]["url"].startswith("http://s3.test/incidents/x/ev-1.jpg")
    assert d["lat"] == pytest.approx(7.111) and d["lon"] == pytest.approx(-73.121)
    assert d["history"][0]["action"] == "CREADO"
    assert set(d["permissions"]["transitions"]) == set()  # operador sin asignar: solo puede tomarlo
    assert d["permissions"]["can_take"] is True
    assert db.audit_logs.count_documents({"action": "VER_INCIDENTE"}) == 1


def test_detalle_anonimo_no_tiene_datos_de_reportante(api):
    d = api.get("/api/py/staff/incidents/BGA-2026-000005", headers=as_(SUPER)).json()
    assert d["reporter"] == {"type": "ANONIMO"}
    assert set(d["permissions"]["transitions"]) == {"EN_REVISION", "ASIGNADO", "NO_PROCEDE"}


def test_detalle_inexistente_404(api):
    assert api.get("/api/py/staff/incidents/BGA-2026-999999", headers=as_(ADMIN)).status_code == 404


# ------------------------------------------------------------------ gestión
def test_operador_toma_un_incidente(api, db):
    r = api.post("/api/py/staff/incidents/BGA-2026-000001/take", headers=as_(OP_A))
    assert r.status_code == 200
    inc = db.incidents.find_one({"radicado": "BGA-2026-000001"})
    assert inc["assigned_to"] == OP_A and inc["status"] == "ASIGNADO" and inc["first_response_at"]
    h = hist(db, "BGA-2026-000001")
    publico = [x for x in h if not x["is_internal"]]
    assert publico[-1]["new_status"] == "ASIGNADO"
    assert "Olga" not in (publico[-1]["note"] or "")  # el ciudadano no ve nombres
    assert any(x["action"] == "ASIGNACION" and x["is_internal"] for x in h)


def test_no_se_puede_tomar_uno_ya_asignado(api):
    assert api.post("/api/py/staff/incidents/BGA-2026-000002/take", headers=as_(OP_B)).status_code == 409


def test_operador_no_gestiona_incidentes_ajenos(api):
    r = api.post("/api/py/staff/incidents/BGA-2026-000002/status", headers=as_(OP_B),
                 json={"status": "EN_ATENCION"})
    assert r.status_code == 403


def test_operador_no_asigna_a_otros(api):
    r = api.post("/api/py/staff/incidents/BGA-2026-000001/assign", headers=as_(OP_A), json={"staff_id": OP_B})
    assert r.status_code == 403


def test_supervisor_asigna(api, db):
    r = api.post("/api/py/staff/incidents/BGA-2026-000001/assign", headers=as_(SUPER), json={"staff_id": OP_B})
    assert r.status_code == 200
    inc = db.incidents.find_one({"radicado": "BGA-2026-000001"})
    assert inc["assigned_to"] == OP_B and inc["assigned_name"] == "Oscar Operador"


def test_asignar_a_quien_no_es_personal_422(api):
    r = api.post("/api/py/staff/incidents/BGA-2026-000001/assign", headers=as_(SUPER), json={"staff_id": CITIZEN})
    assert r.status_code == 422


def test_flujo_completo_y_timeline_publico(api, db):
    h = as_(OP_A)
    assert api.post("/api/py/staff/incidents/BGA-2026-000002/status", headers=h,
                    json={"status": "EN_ATENCION", "internal_note": "Patrulla 12 en camino"}).status_code == 200
    assert api.post("/api/py/staff/incidents/BGA-2026-000002/status", headers=h,
                    json={"status": "CERRADO", "public_message": "Se atendió el caso y se dejó constancia."}
                    ).status_code == 200
    inc = db.incidents.find_one({"radicado": "BGA-2026-000002"})
    assert inc["status"] == "CERRADO" and inc["closed_at"]
    publico = [x for x in hist(db, "BGA-2026-000002") if not x["is_internal"]]
    assert [x["new_status"] for x in publico][-2:] == ["EN_ATENCION", "CERRADO"]
    assert publico[-1]["action"] == "CIERRE"
    assert all("Patrulla" not in (x.get("note") or "") for x in publico)
    assert db.audit_logs.count_documents({"action": "CAMBIO_ESTADO", "actor_id": OP_A}) == 2


def test_transicion_invalida_409(api):
    r = api.post("/api/py/staff/incidents/BGA-2026-000001/status", headers=as_(SUPER), json={"status": "CERRADO",
                                                                                              "public_message": "x" * 20})
    assert r.status_code == 409


@pytest.mark.parametrize("estado", ["CERRADO", "NO_PROCEDE"])
def test_cierre_exige_mensaje(api, estado):
    r = api.post("/api/py/staff/incidents/BGA-2026-000003/status", headers=as_(SUPER), json={"status": estado})
    assert r.status_code in (409, 422)
    if estado == "CERRADO":
        assert r.status_code == 422


def test_solo_supervisor_reabre(api):
    body = {"status": "EN_REVISION", "public_message": "Reabrimos su caso para revisarlo de nuevo."}
    assert api.post("/api/py/staff/incidents/BGA-2026-000004/status", headers=as_(OP_A), json=body).status_code == 403
    assert api.post("/api/py/staff/incidents/BGA-2026-000004/status", headers=as_(SUPER), json=body).status_code == 200


def test_nota_interna_y_mensaje_al_ciudadano(api, db):
    h = as_(OP_A)
    assert api.post("/api/py/staff/incidents/BGA-2026-000002/notes", headers=h,
                    json={"text": "Llamar al reportante", "public": False}).status_code == 201
    assert api.post("/api/py/staff/incidents/BGA-2026-000002/notes", headers=h,
                    json={"text": "Estamos verificando su reporte.", "public": True}).status_code == 201
    acciones = [(x["action"], x["is_internal"]) for x in hist(db, "BGA-2026-000002")]
    assert ("NOTA_INTERNA", True) in acciones and ("MENSAJE_CIUDADANO", False) in acciones


def test_prioridad(api, db):
    r = api.post("/api/py/staff/incidents/BGA-2026-000002/priority", headers=as_(OP_A), json={"priority": "ALTA"})
    assert r.status_code == 200
    assert db.incidents.find_one({"radicado": "BGA-2026-000002"})["priority"] == "ALTA"
    assert api.post("/api/py/staff/incidents/BGA-2026-000002/priority", headers=as_(OP_A),
                    json={"priority": "URGENTISIMA"}).status_code == 422


def test_el_ciudadano_ve_el_cambio_en_su_seguimiento(api, db, monkeypatch):
    """Integración con la app: el timeline público del ciudadano refleja la gestión, sin notas internas."""
    from alertabga.reports.repository import MongoReportRepository

    api.post("/api/py/staff/incidents/BGA-2026-000001/take", headers=as_(OP_A))
    api.post("/api/py/staff/incidents/BGA-2026-000001/notes", headers=as_(OP_A),
             json={"text": "Nota reservada", "public": False})
    repo = MongoReportRepository(db, config=None)  # type: ignore[arg-type]
    iid = db.incidents.find_one({"radicado": "BGA-2026-000001"})["_id"]
    timeline = repo.public_timeline(iid)
    assert [t["new_status"] for t in timeline] == ["RECIBIDO", "ASIGNADO"]
    assert all("reservada" not in (t.get("note") or "") for t in timeline)


# ------------------------------------------------------------------ resúmenes
def test_resumen_del_panel(api):
    r = api.get("/api/py/staff/summary", headers=as_(OP_A))
    assert r.status_code == 200
    s = r.json()
    assert s["open_total"] == 4
    assert s["by_status"]["RECIBIDO"] == 2
    assert s["unassigned_open"] == 2
    assert s["mine_open"] == 1
    assert s["today"] == 2
    assert len(s["last_14_days"]) == 14 and sum(d["count"] for d in s["last_14_days"]) == 4
    assert s["recent"][0]["radicado"] == "BGA-2026-000002"


def test_estadisticas_solo_supervisor(api):
    assert api.get("/api/py/staff/stats", headers=as_(OP_A)).status_code == 403
    r = api.get("/api/py/staff/stats?days=30", headers=as_(SUPER))
    assert r.status_code == 200
    s = r.json()
    assert s["total"] == 4
    assert {c["key"]: c["count"] for c in s["by_category"]} == {"Hurto": 2, "Riñas": 2}
    assert len(s["by_hour"]) == 24 and len(s["by_weekday"]) == 7
    assert s["by_source"] == {"APP_ANONIMO": 3, "APP_AUTENTICADO": 1}


def test_mapa_devuelve_puntos(api):
    r = api.get("/api/py/staff/map?days=30", headers=as_(OP_A))
    pts = r.json()["points"]
    assert len(pts) == 4
    assert {"radicado", "lat", "lon", "status", "category", "priority"} <= set(pts[0])


def test_equipo_para_asignar(api):
    r = api.get("/api/py/staff/team", headers=as_(OP_A))
    assert {m["full_name"] for m in r.json()} == {"Ana Admin", "Sergio Supervisor", "Olga Operadora", "Oscar Operador"}


# ------------------------------------------------------------------ exportación
def test_exportar_csv_sin_datos_personales(api, db):
    db.incidents.update_one({"radicado": "BGA-2026-000001"}, {"$set": {"description": "=HYPERLINK(\"x\")"}})
    assert api.get("/api/py/staff/incidents.csv", headers=as_(OP_A)).status_code == 403
    r = api.get("/api/py/staff/incidents.csv?days=365", headers=as_(SUPER))
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    rows = list(csv.DictReader(io.StringIO(r.text.lstrip("﻿"))))
    assert len(rows) == 5
    assert "laura" not in r.text.lower() and "3001234567" not in r.text
    fila = next(x for x in rows if x["radicado"] == "BGA-2026-000001")
    assert fila["descripcion"].startswith("'=")
    assert db.audit_logs.count_documents({"action": "EXPORTAR_INCIDENTES"}) == 1
