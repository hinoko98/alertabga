-- AlertaBGA · Row Level Security. La API aplica RBAC antes; RLS es la barrera final.

-- ---------------------------------------------------------------- helpers (security definer: evitan recursión de políticas)
create or replace function public.auth_role()
returns text language sql stable security definer set search_path = '' as $$
  select p.role_code from public.profiles p where p.id = auth.uid() and p.active;
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.auth_role() in ('operador','supervisor','administrador'), false);
$$;

-- Operador: solo sus cuadrantes. Supervisor: sus cuadrantes + cola sin cuadrante. Administrador: todo.
create or replace function public.can_access_quadrant(p_quadrant uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case public.auth_role()
    when 'administrador' then true
    when 'supervisor' then p_quadrant is null or exists (
      select 1 from public.profile_quadrants pq where pq.profile_id = auth.uid() and pq.quadrant_id = p_quadrant)
    when 'operador' then p_quadrant is not null and exists (
      select 1 from public.profile_quadrants pq where pq.profile_id = auth.uid() and pq.quadrant_id = p_quadrant)
    else false
  end;
$$;

create or replace function public.staff_can_access_incident(p_incident uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.incidents i
                 where i.id = p_incident and public.can_access_quadrant(i.quadrant_id));
$$;

create or replace function public.is_own_incident(p_incident uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.incidents i where i.id = p_incident and i.reporter_id = auth.uid());
$$;

grant execute on function public.auth_role(), public.is_staff(), public.can_access_quadrant(uuid),
  public.staff_can_access_incident(uuid), public.is_own_incident(uuid) to authenticated;

-- ---------------------------------------------------------------- privilegios de perfil (rol/activo solo administrador)
-- Sin security definer a propósito: current_user debe ser el rol del cliente (authenticated/anon).
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.role_code is distinct from old.role_code or new.active is distinct from old.active)
     and coalesce(public.auth_role(), '') <> 'administrador' then
    raise exception 'Solo un administrador puede cambiar rol o estado' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger profiles_protect_privileges before update on public.profiles
  for each row execute function public.protect_profile_privileges();

-- ---------------------------------------------------------------- activar RLS en todas las tablas
alter table public.roles                  enable row level security;
alter table public.profiles               enable row level security;
alter table public.quadrants              enable row level security;
alter table public.profile_quadrants      enable row level security;
alter table public.categories             enable row level security;
alter table public.incidents              enable row level security;
alter table public.evidence               enable row level security;
alter table public.assignments            enable row level security;
alter table public.incident_history       enable row level security;
alter table public.institutional_messages enable row level security;
alter table public.notifications          enable row level security;
alter table public.audit_logs             enable row level security;
alter table public.app_settings           enable row level security;
alter table public.rate_limits            enable row level security;  -- sin políticas: solo service_role

-- ---------------------------------------------------------------- roles
create policy roles_select on public.roles for select to authenticated using (true);

-- ---------------------------------------------------------------- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.auth_role() in ('supervisor','administrador'));
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_admin_all on public.profiles for all to authenticated
  using (public.auth_role() = 'administrador') with check (public.auth_role() = 'administrador');

-- ---------------------------------------------------------------- quadrants / profile_quadrants
create policy quadrants_select on public.quadrants for select to authenticated using (public.is_staff());
create policy quadrants_admin on public.quadrants for all to authenticated
  using (public.auth_role() = 'administrador') with check (public.auth_role() = 'administrador');

create policy profile_quadrants_select on public.profile_quadrants for select to authenticated
  using (profile_id = auth.uid() or public.auth_role() in ('supervisor','administrador'));
create policy profile_quadrants_admin on public.profile_quadrants for all to authenticated
  using (public.auth_role() = 'administrador') with check (public.auth_role() = 'administrador');

-- ---------------------------------------------------------------- categories
create policy categories_select_active on public.categories for select to anon, authenticated
  using (active or public.auth_role() = 'administrador');
create policy categories_admin on public.categories for all to authenticated
  using (public.auth_role() = 'administrador') with check (public.auth_role() = 'administrador');

-- ---------------------------------------------------------------- incidents (sin INSERT/DELETE para clientes: la creación pasa por la API)
create policy incidents_select on public.incidents for select to authenticated
  using (reporter_id = auth.uid() or (public.is_staff() and public.can_access_quadrant(quadrant_id)));
create policy incidents_update_staff on public.incidents for update to authenticated
  using (public.is_staff() and public.can_access_quadrant(quadrant_id))
  with check (public.is_staff() and public.can_access_quadrant(quadrant_id));

-- ---------------------------------------------------------------- evidence (metadatos; el binario solo vía URL firmada)
create policy evidence_select on public.evidence for select to authenticated
  using (public.staff_can_access_incident(incident_id) or public.is_own_incident(incident_id));

-- ---------------------------------------------------------------- assignments
create policy assignments_select on public.assignments for select to authenticated
  using (public.staff_can_access_incident(incident_id));
create policy assignments_insert on public.assignments for insert to authenticated
  with check (public.auth_role() in ('supervisor','administrador')
              and public.staff_can_access_incident(incident_id)
              and assigned_by = auth.uid());

-- ---------------------------------------------------------------- incident_history
create policy history_select_staff on public.incident_history for select to authenticated
  using (public.staff_can_access_incident(incident_id));
create policy history_select_citizen on public.incident_history for select to authenticated
  using (not is_internal and public.is_own_incident(incident_id));
create policy history_insert_note on public.incident_history for insert to authenticated
  with check (public.staff_can_access_incident(incident_id)
              and actor_id = auth.uid()
              and action = 'NOTA_INTERNA'
              and is_internal);

-- ---------------------------------------------------------------- institutional_messages
create policy messages_select on public.institutional_messages for select to authenticated
  using (public.staff_can_access_incident(incident_id) or public.is_own_incident(incident_id));
create policy messages_insert on public.institutional_messages for insert to authenticated
  with check (public.staff_can_access_incident(incident_id) and author_id = auth.uid());

-- ---------------------------------------------------------------- notifications
create policy notifications_own on public.notifications for select to authenticated using (profile_id = auth.uid());
create policy notifications_mark_read on public.notifications for update to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- ---------------------------------------------------------------- audit_logs (insert solo service_role)
create policy audit_select on public.audit_logs for select to authenticated
  using (public.auth_role() in ('supervisor','administrador'));

-- ---------------------------------------------------------------- app_settings
create policy settings_select on public.app_settings for select to authenticated using (true);
create policy settings_admin on public.app_settings for all to authenticated
  using (public.auth_role() = 'administrador') with check (public.auth_role() = 'administrador');

-- ---------------------------------------------------------------- privilegios por columna: los clientes no tocan campos sellados
revoke insert, update, delete on public.incidents from anon;
revoke all on public.rate_limits from anon, authenticated;
revoke insert, update, delete on public.audit_logs from anon, authenticated;

-- ---------------------------------------------------------------- Realtime (eventos reales de la BD, filtrados por RLS)
alter publication supabase_realtime add table
  public.incidents, public.assignments, public.institutional_messages, public.incident_history;
