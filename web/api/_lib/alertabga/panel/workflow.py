"""Reglas de gestión de incidentes (antes eran triggers de Postgres; ADR 0003, plan Fase 3 §4).

Puro y sin E/S: se prueba directo y lo usa PanelService.
"""

STATUSES = ("RECIBIDO", "EN_REVISION", "ASIGNADO", "EN_ATENCION", "CERRADO", "NO_PROCEDE")
OPEN_STATUSES = ("RECIBIDO", "EN_REVISION", "ASIGNADO", "EN_ATENCION")
CLOSED_STATUSES = ("CERRADO", "NO_PROCEDE")
PRIORITIES = ("BAJA", "MEDIA", "ALTA", "CRITICA")
MANAGERS = frozenset({"supervisor", "administrador"})

TRANSITIONS: dict[str, tuple[str, ...]] = {
    "RECIBIDO": ("EN_REVISION", "ASIGNADO", "NO_PROCEDE"),
    "EN_REVISION": ("ASIGNADO", "NO_PROCEDE"),
    "ASIGNADO": ("EN_ATENCION", "EN_REVISION", "NO_PROCEDE"),
    "EN_ATENCION": ("CERRADO", "ASIGNADO"),
    "CERRADO": ("EN_REVISION",),
    "NO_PROCEDE": ("EN_REVISION",),
}

# Texto que ve el ciudadano cuando el funcionario no escribe un mensaje propio. Nunca lleva nombres.
PUBLIC_TEXT = {
    "EN_REVISION": "Su reporte está en revisión.",
    "ASIGNADO": "Su reporte fue asignado a la unidad responsable.",
    "EN_ATENCION": "La unidad responsable está atendiendo su reporte.",
}


def is_manager(role: str) -> bool:
    return role in MANAGERS


def can_manage(role: str, user_id: str, incident: dict) -> bool:
    """Puede cambiar estado, prioridad y escribir notas en este incidente."""
    return is_manager(role) or (role == "operador" and incident.get("assigned_to") == user_id)


def can_take(role: str, incident: dict) -> bool:
    return role in ("operador", "supervisor", "administrador") and not incident.get("assigned_to") \
        and incident["status"] in ("RECIBIDO", "EN_REVISION")


def allowed_transitions(role: str, user_id: str, incident: dict) -> list[str]:
    if not can_manage(role, user_id, incident):
        return []
    options = list(TRANSITIONS.get(incident["status"], ()))
    if incident["status"] in CLOSED_STATUSES and not is_manager(role):
        return []  # reabrir es de supervisor/administrador
    return options


def needs_message(old: str, new: str) -> bool:
    """Cerrar, marcar "no procede" o reabrir exige un mensaje para el ciudadano."""
    return new in CLOSED_STATUSES or old in CLOSED_STATUSES
