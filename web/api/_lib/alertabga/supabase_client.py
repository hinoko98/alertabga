"""Clientes Supabase. `user_client` actúa con el JWT del usuario (aplica RLS);
`service_client` solo para operaciones de sistema (creación anónima, auditoría, rate limit)."""

from functools import lru_cache

from supabase import Client, create_client

from .config import get_settings


def user_client(token: str) -> Client:
    s = get_settings()
    client = create_client(s.supabase_url, s.supabase_anon_key)
    client.postgrest.auth(token)
    return client


@lru_cache
def service_client() -> Client:
    s = get_settings()
    return create_client(s.supabase_url, s.supabase_service_role_key)
