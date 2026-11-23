"""Administración: solo administrador; validaciones; autoprotección; auditoría."""

import mongomock
import pytest

from conftest import make_token

ADMIN = "aaaaaaaa-0000-0000-0000-000000000001"
OP = "aaaaaaaa-0000-0000-0000-000000000003"


class FakeGateway:
    def __init__(self):
        self.users = {
            ADMIN: {"id": ADMIN, "email": "admin@example.com", "full_name": "Ana Admin", "role": "administrador",
                    "active": True, "created_at": "", "last_sign_in_at": None},
            OP: {"id": OP, "email": "op@example.com", "full_name": "Olga", "role": "operador", "active": True,
                 "created_at": "", "last_sign_in_at": None},
        }
        self.cats = {"c1": {"id": "c1", "name": "Hurto", "description": "", "icon": "x", "color": "#F59E0B",
                            "severity_default": 3, "active": True}}
        self.setting_values = {"rate_limit_reports": {"max": 5, "window_minutes": 60}}

    def list_users(self):
        return list(self.users.values())

    def create_user(self, email, password, full_name):
        from alertabga.admin import Conflict

        if any(u["email"] == email for u in self.users.values()):
            raise Conflict("Ya existe una cuenta con ese correo")
        uid = f"nuevo-{len(self.users)}"
        self.users[uid] = {"id": uid, "email": email, "full_name": full_name, "role": "ciudadano", "active": True,
                           "created_at": "", "last_sign_in_at": None, "password": password}
        return uid

    def update_profile(self, user_id, values):
        u = self.users[user_id]
        if "role_code" in values:
            u["role"] = values["role_code"]
        u.update({k: v for k, v in values.items() if k != "role_code"})

    def list_categories(self):
        return list(self.cats.values())

    def create_category(self, values):
        row = {"id": f"c{len(self.cats) + 1}", "active": True, **values}
        self.cats[row["id"]] = row
        return row

    def update_category(self, category_id, values):
        if category_id not in self.cats:
            return None
        self.cats[category_id].update(values)
        return self.cats[category_id]

    def settings(self):
        return self.setting_values

    def update_setting(self, key, value):
        self.setting_values[key] = value


@pytest.fixture
def env(client, monkeypatch):
    from alertabga import deps
    from alertabga.admin import AdminService
    from alertabga.routers.admin import get_admin_service

    gw = FakeGateway()
    db = mongomock.MongoClient().alertabga
    roles = {ADMIN: "administrador", OP: "operador"}
    monkeypatch.setattr(deps, "fetch_profile",
                        lambda t, uid: {"id": uid, "role_code": roles.get(uid, "ciudadano"), "full_name": None,
                                        "active": True})
    client.app.dependency_overrides[get_admin_service] = lambda: AdminService(gw, db, ADMIN)
    yield client, gw, db
    client.app.dependency_overrides.clear()


def h(uid=ADMIN):
    return {"Authorization": f"Bearer {make_token(uid)}"}


def test_operador_no_entra_a_administracion(client, monkeypatch):
    from alertabga import deps

    monkeypatch.setattr(deps, "fetch_profile",
                        lambda t, uid: {"id": uid, "role_code": "operador", "full_name": None, "active": True})
    assert client.get("/api/py/admin/users", headers=h(OP)).status_code == 403


def test_crear_personal_con_clave_temporal(env):
    client, gw, db = env
    r = client.post("/api/py/admin/users", headers=h(),
                    json={"email": "Nuevo@Example.com", "full_name": "Nuevo Operador", "role": "operador"})
    assert r.status_code == 201
    body = r.json()
    assert body["email"] == "nuevo@example.com" and body["role"] == "operador"
    assert len(body["temporary_password"]) >= 12
    creado = gw.users[body["id"]]
    assert creado["role"] == "operador" and creado["password"] == body["temporary_password"]
    assert db.audit_logs.count_documents({"action": "CREAR_USUARIO"}) == 1


@pytest.mark.parametrize("payload", [
    {"email": "no-es-correo", "full_name": "Nombre Ok", "role": "operador"},
    {"email": "a@example.com", "full_name": "Nombre Ok", "role": "superusuario"},
    {"email": "a@example.com", "full_name": "x", "role": "operador"},
    {"email": "a@example.com", "full_name": "Nombre Ok", "role": "operador", "password": "corta"},
])
def test_crear_personal_valida(env, payload):
    client, _, _ = env
    assert client.post("/api/py/admin/users", headers=h(), json=payload).status_code == 422


def test_correo_duplicado_409(env):
    client, _, _ = env
    r = client.post("/api/py/admin/users", headers=h(), json={"email": "op@example.com", "full_name": "Otra",
                                                              "role": "operador"})
    assert r.status_code == 409


def test_cambiar_rol_y_desactivar(env):
    client, gw, _ = env
    assert client.patch(f"/api/py/admin/users/{OP}", headers=h(), json={"role": "supervisor"}).status_code == 200
    assert client.patch(f"/api/py/admin/users/{OP}", headers=h(), json={"active": False}).status_code == 200
    assert gw.users[OP]["role"] == "supervisor" and gw.users[OP]["active"] is False


@pytest.mark.parametrize("payload", [{"role": "operador"}, {"active": False}])
def test_admin_no_se_quita_privilegios(env, payload):
    client, _, _ = env
    assert client.patch(f"/api/py/admin/users/{ADMIN}", headers=h(), json=payload).status_code == 409


def test_categorias(env):
    client, gw, _ = env
    r = client.post("/api/py/admin/categories", headers=h(),
                    json={"name": "Vandalismo", "color": "#123ABC", "severity_default": 2})
    assert r.status_code == 201
    cid = r.json()["id"]
    assert client.patch(f"/api/py/admin/categories/{cid}", headers=h(), json={"active": False}).status_code == 200
    assert gw.cats[cid]["active"] is False
    assert client.post("/api/py/admin/categories", headers=h(), json={"name": "X", "color": "rojo"}).status_code == 422
    assert client.patch("/api/py/admin/categories/no-existe", headers=h(), json={"active": True}).status_code == 404


def test_ajuste_de_limite(env):
    client, gw, db = env
    r = client.put("/api/py/admin/settings/rate-limit", headers=h(), json={"max": 10, "window_minutes": 30})
    assert r.status_code == 200
    assert gw.setting_values["rate_limit_reports"] == {"max": 10, "window_minutes": 30}
    assert client.put("/api/py/admin/settings/rate-limit", headers=h(),
                      json={"max": 0, "window_minutes": 30}).status_code == 422


def test_auditoria_con_nombres(env):
    client, _, db = env
    client.put("/api/py/admin/settings/rate-limit", headers=h(), json={"max": 8, "window_minutes": 60})
    rows = client.get("/api/py/admin/audit", headers=h()).json()
    assert rows[0]["action"] == "ACTUALIZAR_AJUSTE" and rows[0]["actor"] == "Ana Admin"
