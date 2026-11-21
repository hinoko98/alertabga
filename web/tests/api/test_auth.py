import pytest

from conftest import make_token

USER_ID = "11111111-1111-1111-1111-111111111111"


@pytest.fixture
def fake_profile(monkeypatch):
    from alertabga import deps

    def _fetch(token: str, user_id: str):
        assert user_id == USER_ID
        return {"id": USER_ID, "role_code": "operador", "full_name": "Op Prueba", "active": True}

    monkeypatch.setattr(deps, "fetch_profile", _fetch)


def test_me_without_token_401(client):
    r = client.get("/api/py/me")
    assert r.status_code == 401
    assert r.json() == {"detail": "No autenticado"}


def test_me_bad_signature_401(client, fake_profile):
    token = make_token(secret="otra-clave-distinta-de-al-menos-32-caracteres")
    r = client.get("/api/py/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401
    assert r.json() == {"detail": "No autenticado"}


def test_me_expired_401(client, fake_profile):
    token = make_token(exp_offset=-10)
    r = client.get("/api/py/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401


def test_me_anon_role_token_401(client, fake_profile):
    token = make_token(role="anon")
    r = client.get("/api/py/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401


def test_me_valid_returns_profile_role(client, fake_profile):
    r = client.get("/api/py/me", headers={"Authorization": f"Bearer {make_token()}"})
    assert r.status_code == 200
    assert r.json() == {"id": USER_ID, "role": "operador", "full_name": "Op Prueba"}


def test_inactive_profile_403(client, monkeypatch):
    from alertabga import deps

    monkeypatch.setattr(deps, "fetch_profile",
                        lambda t, u: {"id": USER_ID, "role_code": "operador", "full_name": None, "active": False})
    r = client.get("/api/py/me", headers={"Authorization": f"Bearer {make_token()}"})
    assert r.status_code == 403


def test_require_roles_blocks_citizen():
    from alertabga.deps import CurrentUser, ensure_role
    from fastapi import HTTPException

    citizen = CurrentUser(id=USER_ID, role="ciudadano", full_name=None, token="t")
    with pytest.raises(HTTPException) as exc:
        ensure_role(citizen, {"operador", "supervisor", "administrador"})
    assert exc.value.status_code == 403
