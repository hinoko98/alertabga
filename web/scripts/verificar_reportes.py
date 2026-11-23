"""Verificación E2E de la app ciudadana contra el stack LOCAL (API :8000 + MongoDB :27018 + S3 local).

Flujo: registro → login → reporte autenticado → /mine; reporte anónimo → track → presign → PUT → confirm;
una NOTA_INTERNA insertada en Mongo nunca aparece en el seguimiento; los datos quedan en MongoDB, no en Postgres.
SOLO LOCAL: crea datos rotulados "PRUEBA E2E".
Uso (desde web/):  .venv\\Scripts\\python scripts\\verificar_reportes.py
"""

import os
import secrets
import sys
from datetime import UTC, datetime, timedelta

import httpx
from pymongo import MongoClient

sys.stdout.reconfigure(encoding="utf-8")  # consola de Windows

API = os.environ.get("API_URL", "http://127.0.0.1:8000") + "/api/py"
MONGO = os.environ.get("MONGODB_URI", "mongodb://127.0.0.1:27018")
fallos = 0


def check(nombre: str, ok: bool, extra: str = "") -> None:
    global fallos
    print(f"{'OK   ' if ok else 'FALLA'} {nombre} {extra}")
    fallos += 0 if ok else 1


c = httpx.Client(base_url=API, timeout=20, headers={"X-Device-Id": f"e2e-{os.getpid()}"})
db = MongoClient(MONGO, serverSelectionTimeoutMS=3000).alertabga

# ---------------------------------------------------------------- cuenta ciudadana (MongoDB)
email = f"e2e-{secrets.token_hex(4)}@example.com"
r = c.post("/auth/register", json={"email": email, "password": "Clave-Segura-2026", "full_name": "PRUEBA E2E"})
check("registro ciudadano 201", r.status_code == 201, r.text if r.status_code != 201 else "")
check("cuenta guardada en MongoDB con hash", (doc := db.citizens.find_one({"email": email})) is not None
      and doc["password_hash"].startswith("scrypt$"))
login = c.post("/auth/login", json={"email": email, "password": "Clave-Segura-2026"}).json()
auth = {"Authorization": f"Bearer {login['access_token']}"}
check("perfil /account", c.get("/account", headers=auth).json().get("email") == email)
nuevo = c.post("/auth/refresh", json={"refresh_token": login["refresh_token"]})
check("refresh rota la sesión", nuevo.status_code == 200
      and c.post("/auth/refresh", json={"refresh_token": login["refresh_token"]}).status_code == 401)

# ---------------------------------------------------------------- reportes
cats = c.get("/categories").json()
check("categorías", len(cats) > 0, f"({len(cats)})")
reporte = {"category_id": cats[0]["id"], "description": "PRUEBA E2E — reporte desde script local",
           "occurred_at": (datetime.now(UTC) - timedelta(hours=1)).isoformat(),
           "lat": 7.1193, "lon": -73.1227, "accuracy_m": 15}
b = c.post("/reports", json=reporte, headers=auth)
check("reporte autenticado 201", b.status_code == 201, b.json().get("radicado", b.text))
check("/reports/mine lo incluye", any(x["radicado"] == b.json()["radicado"]
                                      for x in c.get("/reports/mine", headers=auth).json()))

a = c.post("/reports/anonymous", json=reporte).json()
rad, tok, iid = a["radicado"], a["tracking_token"], a["id"]
check("reporte anónimo con código", bool(tok), rad)
inc = db.incidents.find_one({"_id": iid})
check("incidente en MongoDB, token solo como hash", inc is not None and tok not in str(inc))
t = c.post("/reports/track", json={"radicado": rad, "token": tok})
check("track con código", t.status_code == 200 and t.json()["status"] == "RECIBIDO")
m1 = c.post("/reports/track", json={"radicado": rad, "token": "x" * 43})
m2 = c.post("/reports/track", json={"radicado": "BGA-2099-999999", "token": tok})
check("código erróneo y radicado inexistente → mismo 404", m1.status_code == m2.status_code == 404
      and m1.text == m2.text)
check("el ciudadano no ve el anónimo ajeno", c.get(f"/reports/{rad}", headers=auth).status_code == 404)

# ---------------------------------------------------------------- evidencia
foto = b"\xff\xd8\xff\xe0" + b"\x07" * 2044
p = c.post("/evidence/presign", json={"radicado": rad, "mime": "image/jpeg", "size": len(foto), "tracking_token": tok})
check("presign", p.status_code == 200, p.text if p.status_code != 200 else "")
put = httpx.put(p.json()["upload_url"], content=foto, headers=p.json()["headers"])
check("PUT al almacenamiento", put.status_code == 200, f"({put.status_code})")
cf = c.post(f"/evidence/{p.json()['evidence_id']}/confirm", json={"radicado": rad, "tracking_token": tok})
check("confirm → CONFIRMADA", cf.json().get("status") == "CONFIRMADA", cf.text)

# ---------------------------------------------------------------- nota interna nunca visible
db.incident_history.insert_one({"incident_id": iid, "action": "NOTA_INTERNA", "note": "SECRETO-E2E",
                                "is_internal": True, "created_at": datetime.now(UTC), "seq": 9})
db.incident_history.insert_one({"incident_id": iid, "action": "MENSAJE_CIUDADANO", "note": "Mensaje E2E visible",
                                "is_internal": False, "created_at": datetime.now(UTC), "seq": 10})
t2 = c.post("/reports/track", json={"radicado": rad, "token": tok})
check("track oculta la nota interna", "SECRETO-E2E" not in t2.text)
check("track muestra el mensaje institucional", "Mensaje E2E visible" in t2.text)
check("track cuenta la evidencia", t2.json().get("evidence_count") == 1)

print(f"\n{fallos} verificación(es) fallaron" if fallos else "\nTodas las verificaciones pasaron")
sys.exit(1 if fallos else 0)
