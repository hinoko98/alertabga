import os
import time

import jwt
import pytest

TEST_SECRET = "test-jwt-secret-with-at-least-32-characters!!"

os.environ.update(
    {
        "SUPABASE_URL": "http://supabase.test",
        "SUPABASE_ANON_KEY": "anon-test",
        "SUPABASE_SERVICE_ROLE_KEY": "service-test",
        "SUPABASE_JWT_SECRET": TEST_SECRET,
        "API_ALLOWED_ORIGINS": "http://localhost:3000",
        # Aísla las pruebas del .env.local del desarrollador (las variables de entorno tienen prioridad)
        "MONGODB_URI": "",
        "R2_ACCOUNT_ID": "",
        "R2_ACCESS_KEY_ID": "",
        "R2_SECRET_ACCESS_KEY": "",
        "R2_BUCKET": "",
        "R2_ENDPOINT_URL": "",
        "R2_PUBLIC_ENDPOINT_URL": "",
        "RATE_LIMIT_SALT": "sal-de-prueba",
        "CITIZEN_JWT_SECRET": "secreto-ciudadano-de-prueba-con-32-caracteres",
        "SMTP_HOST": "",
    }
)


def make_token(sub: str = "11111111-1111-1111-1111-111111111111", *, secret: str = TEST_SECRET,
               exp_offset: int = 3600, role: str = "authenticated") -> str:
    now = int(time.time())
    payload = {"sub": sub, "role": role, "aud": "authenticated", "iat": now, "exp": now + exp_offset}
    return jwt.encode(payload, secret, algorithm="HS256")


@pytest.fixture
def client():
    from fastapi.testclient import TestClient

    from alertabga.config import get_settings
    from alertabga.main import create_app

    get_settings.cache_clear()
    return TestClient(create_app())


CITIZEN_A = "11111111-1111-1111-1111-111111111111"
CITIZEN_B = "22222222-2222-2222-2222-222222222222"


@pytest.fixture
def citizen_db(client):
    """Mongo en memoria para cuentas ciudadanas; dos ciudadanos de prueba ya registrados."""
    import mongomock

    from alertabga.citizens import get_citizen_service
    from alertabga.citizens.mailer import MemoryMailer
    from alertabga.citizens.security import hash_password
    from alertabga.citizens.service import CitizenService
    from alertabga.config import get_settings
    from alertabga.mongo_store import ensure_indexes

    db = mongomock.MongoClient().alertabga
    ensure_indexes(db)
    for cid, email in ((CITIZEN_A, "a@example.com"), (CITIZEN_B, "b@example.com")):
        db.citizens.insert_one({"_id": cid, "email": email, "password_hash": hash_password("Clave-Segura-1"),
                                "full_name": "Ciudadano Prueba", "active": True})
    mailer = MemoryMailer()
    db.mailer = mailer  # acceso desde las pruebas
    client.app.dependency_overrides[get_citizen_service] = lambda: CitizenService(db, get_settings(), mailer)
    return db


def citizen_auth(cid: str = CITIZEN_A) -> dict:
    from alertabga.citizens.security import issue_access_token

    return {"Authorization": f"Bearer {issue_access_token(cid, os.environ['CITIZEN_JWT_SECRET'], 900)}"}
