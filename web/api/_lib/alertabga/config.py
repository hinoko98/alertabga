from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuración leída de variables de entorno (ver docs/configuracion/variables-entorno.md)."""

    model_config = SettingsConfigDict(env_file=(".env", ".env.local"), extra="ignore")

    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str
    supabase_jwt_secret: str | None = None

    r2_account_id: str | None = None
    r2_access_key_id: str | None = None
    r2_secret_access_key: str | None = None
    r2_bucket: str | None = None
    # Opcionales: en local se usa la interfaz S3 de Supabase Storage como sustituto de R2.
    r2_endpoint_url: str | None = None
    r2_public_endpoint_url: str | None = None  # host que verán los clientes en las URLs firmadas
    r2_region: str = "auto"

    rate_limit_salt: str = ""

    mongodb_uri: str | None = None
    mongodb_db: str = "alertabga"

    api_allowed_origins: str = Field(default="http://localhost:3000")

    @property
    def allowed_origins(self) -> list[str]:
        return [o.strip() for o in self.api_allowed_origins.split(",") if o.strip()]

    @property
    def r2_endpoint(self) -> str | None:
        if self.r2_endpoint_url:
            return self.r2_endpoint_url
        return f"https://{self.r2_account_id}.r2.cloudflarestorage.com" if self.r2_account_id else None

    @property
    def r2_configured(self) -> bool:
        return all([self.r2_endpoint, self.r2_access_key_id, self.r2_secret_access_key, self.r2_bucket])


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
