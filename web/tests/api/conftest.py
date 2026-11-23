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
