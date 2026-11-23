import pytest

from fakes import FakeRepository
from test_reports import USER_A, USER_B, auth, body


class FakeStorage:
    def __init__(self):
        self.objects: dict[str, dict] = {}
        self.deleted: list[str] = []
        self.signed: list[str] = []

    def extension_for(self, mime):
        from alertabga.storage import extension_for
        return extension_for(mime)

    def validate(self, mime, size):
        from alertabga.storage import validate
        validate(mime, size)

    def presign_put(self, key, mime, size):
        self.signed.append(key)
        return f"http://s3.test/evidencias/{key}?X-Amz-Signature=abc"

    def head(self, key):
        return self.objects.get(key)

    def delete(self, key):
        self.deleted.append(key)
        self.objects.pop(key, None)


@pytest.fixture
def repo():
    return FakeRepository()


@pytest.fixture
def store():
    return FakeStorage()


@pytest.fixture
def api(client, repo, store, citizen_db):
    from alertabga.reports import get_report_service
    from alertabga.reports.evidence_service import EvidenceService
    from alertabga.reports.service import ReportService
    from alertabga.routers.evidence import get_evidence_service

    svc = ReportService(repo, "sal")
    client.app.dependency_overrides[get_report_service] = lambda: svc
    client.app.dependency_overrides[get_evidence_service] = lambda: EvidenceService(svc, store)
    return client


@pytest.fixture
def anon_report(api):
    return api.post("/api/py/reports/anonymous", json=body(), headers={"X-Device-Id": "d"}).json()


def presign(api, rep, mime="image/jpeg", size=1000, token="__rep__"):
    tok = rep["tracking_token"] if token == "__rep__" else token
    return api.post("/api/py/evidence/presign",
                    json={"radicado": rep["radicado"], "mime": mime, "size": size, "tracking_token": tok})


def confirm(api, rep, evidence_id, token="__rep__"):
    tok = rep["tracking_token"] if token == "__rep__" else token
    return api.post(f"/api/py/evidence/{evidence_id}/confirm",
                    json={"radicado": rep["radicado"], "tracking_token": tok})


def test_presign_anonimo_ok(api, anon_report, repo):
    r = presign(api, anon_report)
    assert r.status_code == 200
    d = r.json()
    ev = repo.evidence[d["evidence_id"]]
    assert ev["storage_key"] == f"incidents/{anon_report['id']}/{d['evidence_id']}.jpg"
    assert ev["status"] == "PENDIENTE" and ev["uploaded_by"] is None
    assert d["method"] == "PUT" and d["headers"] == {"Content-Type": "image/jpeg"}


def test_cuarto_archivo_409(api, anon_report):
    for _ in range(3):
        assert presign(api, anon_report).status_code == 200
    assert presign(api, anon_report).status_code == 409


def test_rechazadas_no_cuentan_para_el_limite(api, anon_report, repo):
    ids = [presign(api, anon_report).json()["evidence_id"] for _ in range(3)]
    repo.evidence[ids[0]]["status"] = "RECHAZADA"
    assert presign(api, anon_report).status_code == 200


@pytest.mark.parametrize("mime,size", [("image/gif", 100), ("application/pdf", 100),
                                       ("image/jpeg", 0), ("image/png", 5 * 1024 * 1024 + 1)])
def test_mime_o_tamano_invalido_422(api, anon_report, mime, size):
    assert presign(api, anon_report, mime, size).status_code == 422


def test_token_invalido_404(api, anon_report, store):
    r = presign(api, anon_report, token="x" * 43)
    assert r.status_code == 404 and r.json() == {"detail": "Radicado o código no válido"}
    assert presign(api, anon_report, token=None).status_code == 404
    assert store.signed == []


def test_autenticado_no_dueno_404(api):
    rep = api.post("/api/py/reports", json=body(), headers=auth(USER_A)).json()
    payload = {"radicado": rep["radicado"], "mime": "image/jpeg", "size": 10}
    assert api.post("/api/py/evidence/presign", json=payload, headers=auth(USER_B)).status_code == 404
    ok = api.post("/api/py/evidence/presign", json=payload, headers=auth(USER_A))
    assert ok.status_code == 200


def test_autenticado_dueno_registra_uploaded_by(api, repo):
    rep = api.post("/api/py/reports", json=body(), headers=auth(USER_A)).json()
    d = api.post("/api/py/evidence/presign", json={"radicado": rep["radicado"], "mime": "image/png", "size": 10},
                 headers=auth(USER_A)).json()
    assert repo.evidence[d["evidence_id"]]["uploaded_by"] == USER_A


def test_token_invalido_en_bearer_401(api, anon_report):
    r = api.post("/api/py/evidence/presign", headers={"Authorization": "Bearer basura"},
                 json={"radicado": anon_report["radicado"], "mime": "image/jpeg", "size": 1})
    assert r.status_code == 401


def test_confirm_correcto(api, anon_report, repo, store):
    d = presign(api, anon_report, size=1234).json()
    store.objects[repo.evidence[d["evidence_id"]]["storage_key"]] = {"size": 1234, "mime": "image/jpeg"}
    r = confirm(api, anon_report, d["evidence_id"])
    assert r.json() == {"status": "CONFIRMADA"}
    assert repo.evidence[d["evidence_id"]]["confirmed_at"]
    assert repo.audits[-1]["action"] == "EVIDENCIA_SUBIDA" and repo.audits[-1]["actor_role"] == "anonimo"
    # idempotente
    assert confirm(api, anon_report, d["evidence_id"]).json() == {"status": "CONFIRMADA"}


def test_confirm_head_distinto_rechaza_y_borra(api, anon_report, repo, store):
    d = presign(api, anon_report, size=1234).json()
    key = repo.evidence[d["evidence_id"]]["storage_key"]
    store.objects[key] = {"size": 9999999, "mime": "image/jpeg"}
    assert confirm(api, anon_report, d["evidence_id"]).json() == {"status": "RECHAZADA"}
    assert store.deleted == [key] and repo.evidence[d["evidence_id"]]["status"] == "RECHAZADA"


def test_confirm_sin_objeto_409(api, anon_report):
    d = presign(api, anon_report).json()
    assert confirm(api, anon_report, d["evidence_id"]).status_code == 409


def test_confirm_evidencia_de_otro_incidente_404(api, repo, store):
    a = api.post("/api/py/reports/anonymous", json=body(), headers={"X-Device-Id": "a"}).json()
    b = api.post("/api/py/reports/anonymous", json=body(), headers={"X-Device-Id": "b"}).json()
    d = presign(api, a).json()
    assert confirm(api, b, d["evidence_id"]).status_code == 404
    assert confirm(api, a, "no-es-uuid").status_code == 404
    assert confirm(api, a, d["evidence_id"], token="malo").status_code == 404


def test_evidence_count_en_track(api, anon_report, repo, store):
    d = presign(api, anon_report, size=50).json()
    store.objects[repo.evidence[d["evidence_id"]]["storage_key"]] = {"size": 50, "mime": "image/jpeg"}
    confirm(api, anon_report, d["evidence_id"])
    t = api.post("/api/py/reports/track",
                 json={"radicado": anon_report["radicado"], "token": anon_report["tracking_token"]})
    assert t.json()["evidence_count"] == 1


