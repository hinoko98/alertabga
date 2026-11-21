def test_health_ok(client):
    r = client.get("/api/py/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["service"] == "alertabga-api"
    assert "time" in body


def test_health_deps_reports_r2_not_configured(client, monkeypatch):
    from alertabga.routers import health

    monkeypatch.setattr(health, "check_supabase", lambda settings: True)
    r = client.get("/api/py/health/deps")
    assert r.status_code == 200
    body = r.json()
    assert body["supabase"] == "ok"
    assert body["r2"] == "no_configurado"
    assert body["mongodb"] == "no_configurado"
