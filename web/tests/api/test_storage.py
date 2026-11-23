from urllib.parse import urlparse

import pytest


@pytest.fixture
def s3_env(monkeypatch):
    from alertabga import storage
    from alertabga.config import get_settings

    monkeypatch.setenv("R2_ACCESS_KEY_ID", "k")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "s")
    monkeypatch.setenv("R2_BUCKET", "evidencias")
    monkeypatch.setenv("R2_ENDPOINT_URL", "http://127.0.0.1:54321/storage/v1/s3")
    monkeypatch.setenv("R2_PUBLIC_ENDPOINT_URL", "http://10.0.2.2:54321/storage/v1/s3")
    monkeypatch.setenv("R2_REGION", "local")
    get_settings.cache_clear()
    storage.reset_clients()
    yield storage
    get_settings.cache_clear()
    storage.reset_clients()


def test_configurado_con_endpoint_sin_account_id(s3_env):
    from alertabga.config import get_settings

    assert get_settings().r2_configured is True


def test_presign_put_rechaza_mime(s3_env):
    with pytest.raises(ValueError):
        s3_env.presign_put("incidents/x/y.gif", "image/gif", 100)


@pytest.mark.parametrize("size", [0, 5 * 1024 * 1024 + 1])
def test_presign_put_rechaza_tamano(s3_env, size):
    with pytest.raises(ValueError):
        s3_env.presign_put("incidents/x/y.jpg", "image/jpeg", size)


def test_presign_put_usa_endpoint_publico(s3_env):
    url = s3_env.presign_put("incidents/x/y.jpg", "image/jpeg", 1000)
    u = urlparse(url)
    assert u.netloc == "10.0.2.2:54321"
    assert u.path == "/storage/v1/s3/evidencias/incidents/x/y.jpg"
    assert "X-Amz-Signature=" in u.query


def test_sin_configuracion_lanza(monkeypatch):
    from alertabga import storage
    from alertabga.config import get_settings

    get_settings.cache_clear()
    storage.reset_clients()
    with pytest.raises(storage.StorageNotConfigured):
        storage.presign_put("incidents/x/y.jpg", "image/jpeg", 1000)
