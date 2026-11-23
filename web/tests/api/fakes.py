"""Repositorio en memoria que imita los triggers relevantes de Postgres (radicado, historial CREADO)."""

import uuid
from datetime import UTC, datetime

CAT_ID = "aaaaaaaa-0000-0000-0000-000000000001"
CAT_INACTIVA = "aaaaaaaa-0000-0000-0000-000000000002"


class FakeRepository:
    def __init__(self, max_reports: int = 5):
        self.categories = {
            CAT_ID: {"id": CAT_ID, "name": "Hurto", "description": "", "icon": "wallet",
                     "color": "#F59E0B", "active": True},
            CAT_INACTIVA: {"id": CAT_INACTIVA, "name": "Vieja", "description": "", "icon": "x",
                           "color": "#000000", "active": False},
        }
        self.incidents: dict[str, dict] = {}
        self.history: list[dict] = []
        self.evidence: dict[str, dict] = {}
        self.audits: list[dict] = []
        self.hits: dict[str, int] = {}
        self.max_reports = max_reports
        self._seq = 0

    # categorías
    def active_category(self, category_id):
        c = self.categories.get(category_id)
        return {"id": c["id"], "name": c["name"]} if c and c["active"] else None

    def active_categories(self):
        return [{k: c[k] for k in ("id", "name", "description", "icon", "color")}
                for c in self.categories.values() if c["active"]]

    # rate limit
    def rate_limit_setting(self):
        return {"max": self.max_reports, "window_minutes": 60}

    def territorial_scope(self):
        return {"min_lat": 7.03, "max_lat": 7.25, "min_lon": -73.20, "max_lon": -73.03}

    def hit_rate_limit(self, key, max_hits, window_minutes):
        self.hits[key] = self.hits.get(key, 0) + 1
        return self.hits[key] <= max_hits

    # incidentes
    def insert_incident(self, row):
        self._seq += 1
        now = datetime.now(UTC).isoformat()
        inc = {**row, "id": str(uuid.uuid4()), "radicado": f"BGA-2026-{self._seq:06d}", "received_at": now,
               "status": "RECIBIDO", "category": self.categories[row["category_id"]]["name"]}
        self.incidents[inc["id"]] = inc
        self.history.append({"incident_id": inc["id"], "action": "CREADO", "new_status": "RECIBIDO",
                             "note": "Reporte recibido", "is_internal": False, "created_at": now})
        return {k: inc[k] for k in ("id", "radicado", "received_at", "status", "out_of_scope")}

    def find_by_radicado(self, radicado):
        return next((dict(i) for i in self.incidents.values() if i["radicado"] == radicado), None)

    def public_timeline(self, incident_id):
        allowed = ("CREADO", "CAMBIO_ESTADO", "CIERRE", "MENSAJE_CIUDADANO")
        return [h for h in self.history
                if h["incident_id"] == incident_id and not h["is_internal"] and h["action"] in allowed]

    def list_mine(self, user_id):
        return [{"radicado": i["radicado"], "status": i["status"], "received_at": i["received_at"],
                 "category": i["category"]} for i in self.incidents.values() if i["reporter_id"] == user_id]

    # evidencias
    def count_evidence(self, incident_id, statuses):
        return sum(1 for e in self.evidence.values() if e["incident_id"] == incident_id and e["status"] in statuses)

    def insert_evidence(self, row):
        e = {"status": "PENDIENTE", **row}
        self.evidence[e["id"]] = e
        return e

    def find_evidence(self, evidence_id, incident_id):
        e = self.evidence.get(evidence_id)
        return dict(e) if e and e["incident_id"] == incident_id else None

    def update_evidence(self, evidence_id, values):
        self.evidence[evidence_id].update(values)

    def audit(self, action, entity, entity_id, actor_id, actor_role, metadata=None, ip_hash=None):
        self.audits.append({"action": action, "entity_id": entity_id, "actor_id": actor_id,
                            "actor_role": actor_role, "metadata": metadata or {}, "ip_hash": ip_hash})
