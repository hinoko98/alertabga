"""Siembra reportes de DEMOSTRACIÓN en MongoDB local para ver el panel con datos (solo desarrollo).

Uso (desde web/):
    .venv\\Scripts\\python scripts\\sembrar_demo.py            # 80 reportes de los últimos 45 días
    .venv\\Scripts\\python scripts\\sembrar_demo.py --n 200
    .venv\\Scripts\\python scripts\\sembrar_demo.py --borrar   # elimina solo los de demostración

Los documentos llevan `demo: true` y radicado `BGA-DEMO-NNNNNN`, así nunca se confunden con reportes reales.
"""

import argparse
import json
import random
import sys
import urllib.request
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

from pymongo import MongoClient

ROOT = Path(__file__).resolve().parents[1]

# Puntos de referencia reales de Bucaramanga (barrio, lat, lon)
LUGARES = [
    ("Centro", 7.1190, -73.1260), ("Cabecera del Llano", 7.1170, -73.1080), ("San Francisco", 7.1240, -73.1200),
    ("La Concordia", 7.1130, -73.1150), ("Provenza", 7.0900, -73.1080), ("Real de Minas", 7.1060, -73.1270),
    ("Mutis", 7.1060, -73.1390), ("Ciudadela Real de Minas", 7.1020, -73.1300), ("Girardot", 7.1300, -73.1330),
    ("Norte - Kennedy", 7.1500, -73.1270), ("Álvarez", 7.1210, -73.1110), ("Diamante II", 7.0960, -73.1170),
    ("La Victoria", 7.1090, -73.1190), ("Lagos del Cacique", 7.0990, -73.1040), ("Morrorico", 7.1250, -73.1000),
]
TEXTOS = {
    "Hurto": ["Me robaron el celular saliendo del bus, dos hombres en moto.",
              "Hurto a mano armada en la tienda de la esquina, se llevaron el dinero de la caja.",
              "Abrieron el carro y se llevaron el maletín con el computador.",
              "Raponazo a una señora cerca del parque, el ladrón huyó a pie hacia la carrera 27."],
    "Riñas y agresiones": ["Pelea entre varios jóvenes frente al establecimiento, hay una persona herida.",
                           "Riña en la cancha del barrio, lanzan piedras y botellas.",
                           "Discusión entre vecinos terminó en agresión física, piden apoyo.",
                           "Grupo de personas en estado de embriaguez agrediendo a transeúntes."],
    "Robo de vehículos": ["Se robaron una moto parqueada frente a la casa, placa terminada en 45C.",
                          "Hurto de bicicleta amarrada en el andén del centro comercial.",
                          "Vieron a dos personas forzando la chapa de un carro estacionado.",
                          "Robo de motocicleta en el semáforo, el conductor fue amenazado con arma blanca."],
}
FLUJOS = [  # (estado final, probabilidad)
    ("RECIBIDO", 0.22), ("EN_REVISION", 0.10), ("ASIGNADO", 0.16), ("EN_ATENCION", 0.14),
    ("CERRADO", 0.30), ("NO_PROCEDE", 0.08),
]
CAMINO = {"RECIBIDO": [], "EN_REVISION": ["EN_REVISION"], "ASIGNADO": ["ASIGNADO"],
          "EN_ATENCION": ["ASIGNADO", "EN_ATENCION"], "CERRADO": ["ASIGNADO", "EN_ATENCION", "CERRADO"],
          "NO_PROCEDE": ["EN_REVISION", "NO_PROCEDE"]}
PUBLICO = {"EN_REVISION": "Su reporte está en revisión.", "ASIGNADO": "Su reporte fue asignado a la unidad responsable.",
           "EN_ATENCION": "La unidad responsable está atendiendo su reporte.",
           "CERRADO": "Se atendió el caso. Gracias por reportar.",
           "NO_PROCEDE": "El reporte no corresponde a un incidente de seguridad atendible por esta vía."}


def env() -> dict[str, str]:
    out = {}
    for line in (ROOT / ".env.local").read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def supabase_get(e: dict, path: str) -> list[dict]:
    req = urllib.request.Request(f"{e['SUPABASE_URL']}/rest/v1/{path}",
                                 headers={"apikey": e["SUPABASE_SERVICE_ROLE_KEY"],
                                          "Authorization": f"Bearer {e['SUPABASE_SERVICE_ROLE_KEY']}"})
    with urllib.request.urlopen(req, timeout=10) as r:  # noqa: S310 (URL local de .env.local)
        return json.loads(r.read())


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=80)
    ap.add_argument("--dias", type=int, default=45)
    ap.add_argument("--borrar", action="store_true")
    args = ap.parse_args()

    e = env()
    if "127.0.0.1" not in e.get("SUPABASE_URL", "") and "localhost" not in e.get("SUPABASE_URL", ""):
        sys.exit("Este script es solo para el entorno local.")
    db = MongoClient("mongodb://127.0.0.1:27018", serverSelectionTimeoutMS=3000)[e.get("MONGODB_DB", "alertabga")]

    ids = [d["_id"] for d in db.incidents.find({"demo": True}, {"_id": 1})]
    if ids:
        db.incident_history.delete_many({"incident_id": {"$in": ids}})
        db.incidents.delete_many({"_id": {"$in": ids}})
    print(f"Eliminados {len(ids)} reportes de demostración anteriores.")
    if args.borrar:
        return

    cats = supabase_get(e, "categories?select=id,name&active=eq.true")
    staff = supabase_get(e, "profiles?select=id,full_name,role_code&role_code=in.(operador,supervisor)&active=eq.true")
    if not cats or not staff:
        sys.exit("Faltan categorías o personal (ejecute scripts\\usuarios-demo.ps1).")

    rng = random.Random(2026)
    now = datetime.now(UTC)
    incidents, history = [], []
    for i in range(1, args.n + 1):
        cat = rng.choice(cats)
        barrio, lat, lon = rng.choice(LUGARES)
        # más reportes en la tarde-noche y en días recientes
        received = now - timedelta(days=rng.random() ** 1.6 * args.dias, hours=rng.choice([0, 0, 1, 2, 3, 5, 8]),
                                   minutes=rng.randint(0, 59))
        final = rng.choices([f for f, _ in FLUJOS], weights=[p for _, p in FLUJOS])[0]
        if (now - received) < timedelta(hours=6) and final in ("CERRADO", "NO_PROCEDE"):
            final = "RECIBIDO"
        iid = str(uuid.uuid4())
        assignee = rng.choice(staff) if final in ("ASIGNADO", "EN_ATENCION", "CERRADO") else None
        doc = {
            "_id": iid, "radicado": f"BGA-DEMO-{i:06d}", "demo": True, "category_id": cat["id"],
            "category_name": cat["name"], "description": rng.choice(TEXTOS.get(cat["name"], ["Reporte de prueba."])),
            "additional_info": None, "occurred_at": received - timedelta(minutes=rng.randint(5, 180)),
            "received_at": received,
            "location": {"type": "Point", "coordinates": [lon + rng.gauss(0, 0.004), lat + rng.gauss(0, 0.004)]},
            "accuracy_m": rng.choice([8, 12, 20, 35]), "location_manual": rng.random() < 0.2,
            "address_text": f"Barrio {barrio}", "status": final,
            "priority": rng.choices(["BAJA", "MEDIA", "ALTA", "CRITICA"], weights=[2, 6, 3, 1])[0],
            "verification_level": "REPORTE_CIUDADANO", "source": rng.choice(["APP_ANONIMO", "APP_AUTENTICADO"]),
            "reporter_id": None, "anon_token_hash": "demo", "quadrant_id": None,
            "assigned_to": assignee["id"] if assignee else None,
            "assigned_name": assignee["full_name"] if assignee else None, "out_of_scope": False,
        }
        history.append({"incident_id": iid, "actor_id": None, "action": "CREADO", "old_status": None,
                        "new_status": "RECIBIDO", "note": "Reporte recibido", "is_internal": False, "metadata": {},
                        "created_at": received, "seq": 0})
        t, prev, seq = received, "RECIBIDO", 1
        for st in CAMINO[final]:
            t += timedelta(minutes=rng.randint(8, 240))
            if t > now:
                t = now - timedelta(minutes=1)
            actor = assignee or rng.choice(staff)
            if st == "ASIGNADO" and assignee:
                history.append({"incident_id": iid, "actor_id": actor["id"], "action": "ASIGNACION", "old_status": None,
                                "new_status": None, "note": f"Asignado a {assignee['full_name']}", "is_internal": True,
                                "metadata": {}, "created_at": t, "seq": seq})
                seq += 1
            history.append({"incident_id": iid, "actor_id": actor["id"],
                            "action": "CIERRE" if st in ("CERRADO", "NO_PROCEDE") else "CAMBIO_ESTADO",
                            "old_status": prev, "new_status": st, "note": PUBLICO[st], "is_internal": False,
                            "metadata": {}, "created_at": t, "seq": seq})
            if seq == 1 or "first_response_at" not in doc:
                doc["first_response_at"] = t
            if st in ("CERRADO", "NO_PROCEDE"):
                doc["closed_at"] = t
            prev, seq = st, seq + 1
        doc["updated_at"] = t
        incidents.append(doc)

    db.incidents.insert_many(incidents)
    db.incident_history.insert_many(history)
    print(f"Sembrados {len(incidents)} reportes de demostración (BGA-DEMO-*) en los últimos {args.dias} días.")


if __name__ == "__main__":
    main()
