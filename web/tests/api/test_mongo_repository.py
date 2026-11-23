"""Repositorio Mongo de reportes y rate limit (lo que antes garantizaban los triggers de Postgres)."""

from datetime import UTC, datetime, timedelta

import mongomock
import pytest

from fakes import CAT_ID


class Config:
    def categories(self):
        return [{"id": CAT_ID, "name": "Hurto", "description": "", "icon": "wallet", "color": "#F59E0B"}]

    def setting(self, key):
        return {"territorial_scope": {"min_lat": 7.03, "max_lat": 7.25, "min_lon": -73.20, "max_lon": -73.03},
                "rate_limit_reports": {"max": 2, "window_minutes": 60}}.get(key)


@pytest.fixture
def repo():
    from alertabga.mongo_store import ensure_indexes
    from alertabga.reports.repository import MongoReportRepository

    db = mongomock.MongoClient().alertabga
    ensure_indexes(db)
    return MongoReportRepository(db, Config())


def row(**kw):
    r = {"category_id": CAT_ID, "category_name": "Hurto", "description": "Descripción suficiente",
         "occurred_at": datetime.now(UTC).isoformat(), "lat": 7.12, "lon": -73.12, "source": "APP_ANONIMO",
         "reporter_id": None, "anon_token_hash": "h", "out_of_scope": False}
    r.update(kw)
    return r


def test_radicado_consecutivo_y_unico(repo):
    a = repo.insert_incident(row())
    b = repo.insert_incident(row())
    year = datetime.now(UTC).year
    assert a["radicado"].startswith("BGA-") and a["radicado"] != b["radicado"]
    assert int(b["radicado"].rsplit("-", 1)[1]) == int(a["radicado"].rsplit("-", 1)[1]) + 1
    assert a["radicado"].split("-")[1] in (str(year), str(year - 1))


def test_insert_crea_historial_publico_y_geojson(repo):
    a = repo.insert_incident(row())
    doc = repo.db.incidents.find_one({"_id": a["id"]})
    assert doc["location"] == {"type": "Point", "coordinates": [-73.12, 7.12]}
    assert doc["status"] == "RECIBIDO" and doc["verification_level"] == "REPORTE_CIUDADANO"
    assert repo.public_timeline(a["id"])[0]["action"] == "CREADO"


def test_timeline_excluye_internos_y_acciones_no_publicas(repo):
    a = repo.insert_incident(row())
    now = datetime.now(UTC)
    repo.db.incident_history.insert_many([
        {"incident_id": a["id"], "action": "NOTA_INTERNA", "note": "x", "is_internal": True, "created_at": now, "seq": 1},
        {"incident_id": a["id"], "action": "ASIGNACION", "note": "y", "is_internal": False, "created_at": now, "seq": 2},
        {"incident_id": a["id"], "action": "MENSAJE_CIUDADANO", "note": "Hola", "is_internal": False,
         "created_at": now + timedelta(seconds=1), "seq": 3},
    ])
    acts = [h["action"] for h in repo.public_timeline(a["id"])]
    assert acts == ["CREADO", "MENSAJE_CIUDADANO"]


def test_find_y_list_mine(repo):
    a = repo.insert_incident(row(source="APP_AUTENTICADO", reporter_id="u1", anon_token_hash=None))
    repo.insert_incident(row(source="APP_AUTENTICADO", reporter_id="u2", anon_token_hash=None))
    found = repo.find_by_radicado(a["radicado"])
    assert found["reporter_id"] == "u1" and found["category"] == "Hurto"
    assert isinstance(found["occurred_at"], str)
    assert [r["radicado"] for r in repo.list_mine("u1")] == [a["radicado"]]
    assert repo.find_by_radicado("BGA-2026-999999") is None


def test_evidencias(repo):
    a = repo.insert_incident(row())
    repo.insert_evidence({"id": "e1", "incident_id": a["id"], "storage_key": "k1", "mime_type": "image/jpeg",
                          "size_bytes": 10, "uploaded_by": None})
    assert repo.count_evidence(a["id"], ("PENDIENTE",)) == 1
    repo.update_evidence("e1", {"status": "CONFIRMADA", "confirmed_at": datetime.now(UTC).isoformat()})
    assert repo.find_evidence("e1", a["id"])["status"] == "CONFIRMADA"
    assert repo.find_evidence("e1", "otro-incidente") is None


def test_rate_limit_ventana(repo):
    from alertabga.mongo_store import hit_rate_limit

    # hora real: el índice TTL (simulado por mongomock) borra ventanas ya vencidas
    t = datetime.now(UTC).replace(minute=5, second=0, microsecond=0)
    assert [hit_rate_limit(repo.db, "k", 2, 60, now=t) for _ in range(3)] == [True, True, False]
    assert hit_rate_limit(repo.db, "k", 2, 60, now=t + timedelta(hours=1)) is True


def test_config_desde_fuente(repo):
    assert repo.active_category(CAT_ID)["name"] == "Hurto"
    assert repo.active_category("otra") is None
    assert repo.rate_limit_setting()["max"] == 2


def test_auditoria(repo):
    repo.audit("REPORTE_CREADO", "incidents", "i1", None, "anonimo", {"a": 1}, "iphash")
    assert repo.db.audit_logs.find_one({"entity_id": "i1"})["action"] == "REPORTE_CREADO"
