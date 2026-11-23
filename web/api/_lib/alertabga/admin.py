"""Administración (Fase 3): personal, categorías, ajustes y auditoría.

Perfiles, categorías y ajustes se escriben con el **token del administrador**: la RLS de Supabase y el trigger
`protect_profile_privileges` siguen siendo la barrera final aunque la API tuviera un fallo de autorización.
La clave de servicio solo se usa para Supabase Auth (crear cuentas y leer correos).
"""

import re
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

STAFF_ROLES = ("operador", "supervisor", "administrador")
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[A-Za-z]{2,}$")
COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


class InvalidData(Exception):
    pass


class Conflict(Exception):
    pass


class NotFound(Exception):
    pass


class AdminGateway(Protocol):
    def list_users(self) -> list[dict]: ...
    def create_user(self, email: str, password: str, full_name: str) -> str: ...
    def update_profile(self, user_id: str, values: dict) -> None: ...
    def list_categories(self) -> list[dict]: ...
    def create_category(self, values: dict) -> dict: ...
    def update_category(self, category_id: str, values: dict) -> dict | None: ...
    def settings(self) -> dict[str, Any]: ...
    def update_setting(self, key: str, value: dict) -> None: ...


class SupabaseAdminGateway:
    def __init__(self, admin_token: str) -> None:
        from .supabase_client import service_client, user_client

        self.as_admin = user_client(admin_token)  # aplica RLS con el rol del administrador
        self.service = service_client()

    def list_users(self) -> list[dict]:
        profiles = {p["id"]: p for p in (self.as_admin.table("profiles")
                                         .select("id, full_name, role_code, active, created_at").execute().data or [])}
        users = self.service.auth.admin.list_users(per_page=1000)
        out = []
        for u in users:
            p = profiles.get(u.id)
            if not p:
                continue
            out.append({"id": u.id, "email": u.email, "full_name": p.get("full_name"), "role": p["role_code"],
                        "active": p["active"], "created_at": str(p.get("created_at") or ""),
                        "last_sign_in_at": str(u.last_sign_in_at) if u.last_sign_in_at else None})
        return out

    def create_user(self, email: str, password: str, full_name: str) -> str:
        try:
            res = self.service.auth.admin.create_user({
                "email": email, "password": password, "email_confirm": True, "user_metadata": {"full_name": full_name}})
        except Exception as e:  # p. ej. correo ya registrado
            if "already" in str(e).lower() or "registered" in str(e).lower():
                raise Conflict("Ya existe una cuenta con ese correo") from e
            raise
        return res.user.id

    def update_profile(self, user_id: str, values: dict) -> None:
        self.as_admin.table("profiles").update(values).eq("id", user_id).execute()

    def list_categories(self) -> list[dict]:
        return self.as_admin.table("categories").select(
            "id, name, description, icon, color, severity_default, active").order("name").execute().data or []

    def create_category(self, values: dict) -> dict:
        try:
            return self.as_admin.table("categories").insert(values).execute().data[0]
        except Exception as e:
            if "duplicate" in str(e).lower() or "23505" in str(e):
                raise Conflict("Ya existe una categoría con ese nombre") from e
            raise

    def update_category(self, category_id: str, values: dict) -> dict | None:
        try:
            data = self.as_admin.table("categories").update(values).eq("id", category_id).execute().data
        except Exception as e:
            if "duplicate" in str(e).lower() or "23505" in str(e):
                raise Conflict("Ya existe una categoría con ese nombre") from e
            raise
        return data[0] if data else None

    def settings(self) -> dict[str, Any]:
        rows = self.as_admin.table("app_settings").select("key, value").execute().data or []
        return {r["key"]: r["value"] for r in rows}

    def update_setting(self, key: str, value: dict) -> None:
        self.as_admin.table("app_settings").update({"value": value}).eq("key", key).execute()


class AdminService:
    def __init__(self, gateway: AdminGateway, db: Any | None, actor_id: str) -> None:
        self.gw = gateway
        self.db = db
        self.actor_id = actor_id

    def _audit(self, action: str, entity: str, entity_id: str | None, metadata: dict | None = None) -> None:
        if self.db is not None:
            from .mongo_store import write_audit

            write_audit(self.db, action, entity, entity_id, self.actor_id, "administrador", metadata)

    # --------------------------------------------------------------- personal
    def users(self) -> list[dict]:
        return sorted(self.gw.list_users(), key=lambda u: (u["role"] not in STAFF_ROLES, u["role"], u["email"] or ""))

    def create_staff(self, email: str, full_name: str, role: str, password: str | None) -> dict:
        email = email.strip().lower()
        if not EMAIL_RE.match(email):
            raise InvalidData("Correo no válido")
        if role not in STAFF_ROLES:
            raise InvalidData("Rol no válido")
        name = full_name.strip()
        if not 3 <= len(name) <= 120:
            raise InvalidData("Escriba el nombre completo")
        generated = password is None
        if password is None:
            password = secrets.token_urlsafe(12)
        elif len(password) < 10:
            raise InvalidData("La contraseña debe tener al menos 10 caracteres")
        user_id = self.gw.create_user(email, password, name)
        self.gw.update_profile(user_id, {"role_code": role, "full_name": name, "active": True})
        self._audit("CREAR_USUARIO", "profile", user_id, {"rol": role})
        return {"id": user_id, "email": email, "role": role,
                "temporary_password": password if generated else None}

    def update_staff(self, user_id: str, role: str | None, active: bool | None, full_name: str | None) -> dict:
        if user_id == self.actor_id and (role not in (None, "administrador") or active is False):
            raise Conflict("No puede quitarse su propio rol de administrador ni desactivar su cuenta")
        values: dict[str, Any] = {}
        if role is not None:
            if role not in (*STAFF_ROLES, "ciudadano"):
                raise InvalidData("Rol no válido")
            values["role_code"] = role
        if active is not None:
            values["active"] = active
        if full_name is not None:
            if not 3 <= len(full_name.strip()) <= 120:
                raise InvalidData("Escriba el nombre completo")
            values["full_name"] = full_name.strip()
        if not values:
            raise InvalidData("Nada que actualizar")
        self.gw.update_profile(user_id, values)
        self._audit("ACTUALIZAR_USUARIO", "profile", user_id, values)
        return {"id": user_id, **values}

    # --------------------------------------------------------------- categorías
    @staticmethod
    def _category_values(data: dict, partial: bool) -> dict:
        v: dict[str, Any] = {}
        if "name" in data or not partial:
            name = (data.get("name") or "").strip()
            if not 2 <= len(name) <= 80:
                raise InvalidData("El nombre debe tener entre 2 y 80 caracteres")
            v["name"] = name
        if "description" in data:
            desc = (data.get("description") or "").strip()
            if len(desc) > 300:
                raise InvalidData("La descripción admite máximo 300 caracteres")
            v["description"] = desc
        if "color" in data:
            if not COLOR_RE.match(data["color"] or ""):
                raise InvalidData("Color no válido (formato #RRGGBB)")
            v["color"] = data["color"]
        if "severity_default" in data:
            sev = data["severity_default"]
            if not isinstance(sev, int) or not 1 <= sev <= 5:
                raise InvalidData("La severidad va de 1 a 5")
            v["severity_default"] = sev
        if "icon" in data:
            v["icon"] = str(data["icon"])[:40]
        if "active" in data:
            v["active"] = bool(data["active"])
        return v

    def categories(self) -> list[dict]:
        return self.gw.list_categories()

    def create_category(self, data: dict) -> dict:
        row = self.gw.create_category(self._category_values(data, partial=False))
        self._audit("CREAR_CATEGORIA", "category", row.get("id"), {"nombre": row.get("name")})
        return row

    def update_category(self, category_id: str, data: dict) -> dict:
        values = self._category_values(data, partial=True)
        if not values:
            raise InvalidData("Nada que actualizar")
        row = self.gw.update_category(category_id, values)
        if row is None:
            raise NotFound()
        self._audit("ACTUALIZAR_CATEGORIA", "category", category_id, values)
        return row

    # --------------------------------------------------------------- ajustes
    def settings(self) -> dict:
        return self.gw.settings()

    def update_rate_limit(self, max_reports: int, window_minutes: int) -> dict:
        if not 1 <= max_reports <= 100 or not 5 <= window_minutes <= 1440:
            raise InvalidData("Use entre 1 y 100 reportes en una ventana de 5 a 1440 minutos")
        value = {"max": max_reports, "window_minutes": window_minutes}
        self.gw.update_setting("rate_limit_reports", value)
        self._audit("ACTUALIZAR_AJUSTE", "app_settings", "rate_limit_reports", value)
        return value

    # --------------------------------------------------------------- auditoría y ciudadanos
    def audit_log(self, limit: int, action: str | None, names: dict[str, str]) -> list[dict]:
        if self.db is None:
            return []
        q = {"action": action} if action else {}
        rows = self.db.audit_logs.find(q, {"_id": 0}).sort("created_at", -1).limit(limit)
        out = []
        for r in rows:
            at = r.get("created_at")
            out.append({"at": (at if at.tzinfo else at.replace(tzinfo=UTC)).isoformat() if isinstance(at, datetime) else at,
                        "action": r.get("action"), "entity": r.get("entity"), "entity_id": r.get("entity_id"),
                        "actor": names.get(r.get("actor_id") or "", "Ciudadano" if r.get("actor_role") == "ciudadano"
                                           else ("Anónimo" if not r.get("actor_id") else "—")),
                        "actor_role": r.get("actor_role"), "metadata": r.get("metadata") or {}})
        return out

    def citizens_summary(self) -> dict:
        if self.db is None:
            return {"total": 0, "active": 0, "last_7_days": 0}
        since = datetime.now(UTC) - timedelta(days=7)
        return {"total": self.db.citizens.count_documents({}),
                "active": self.db.citizens.count_documents({"active": True}),
                "last_7_days": self.db.citizens.count_documents({"created_at": {"$gte": since}})}
