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

    mongodb_uri: str | None = None
    mongodb_db: str = "alertabga"

    api_allowed_origins: str = Field(default="http://localhost:3000")

    @property
    def allowed_origins(self) -> list[str]:
        return [o.strip() for o in self.api_allowed_origins.split(",") if o.strip()]

    @property
    def r2_configured(self) -> bool:
        return all([self.r2_account_id, self.r2_access_key_id, self.r2_secret_access_key, self.r2_bucket])


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
