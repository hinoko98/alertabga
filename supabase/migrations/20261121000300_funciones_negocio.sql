-- AlertaBGA · Funciones y triggers de reglas de negocio

-- ---------------------------------------------------------------- utilidades
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch   before update on public.profiles   for each row execute function public.touch_updated_at();
create trigger categories_touch before update on public.categories for each row execute function public.touch_updated_at();
create trigger quadrants_touch  before update on public.quadrants  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------- radicado BGA-AAAA-NNNNNN
create or replace function public.generate_radicado()
returns text language sql volatile security definer set search_path = '' as $$
  select 'BGA-' || to_char(now() at time zone 'America/Bogota', 'YYYY') || '-'
         || lpad(nextval('public.incident_radicado_seq')::text, 6, '0');
$$;

-- ---------------------------------------------------------------- cuadrante por polígono (null si no hay polígono oficial)
create or replace function public.assign_quadrant(p_location extensions.geography)
returns uuid language sql stable security definer set search_path = '' as $$
  select q.id
  from public.quadrants q
  where q.active and q.boundary is not null
    and extensions.st_covers(q.boundary, p_location)
  order by q.code
  limit 1;
$$;

-- ---------------------------------------------------------------- ámbito territorial configurado
create or replace function public.in_territorial_scope(p_location extensions.geography)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  s   jsonb;
  lat double precision := extensions.st_y(p_location::extensions.geometry);
  lon double precision := extensions.st_x(p_location::extensions.geometry);
begin
  select value into s from public.app_settings where key = 'territorial_scope';
  if s is null then
    return true;
  end if;
  return lat between (s->>'min_lat')::float8 and (s->>'max_lat')::float8
     and lon between (s->>'min_lon')::float8 and (s->>'max_lon')::float8;
end $$;

-- ---------------------------------------------------------------- rate limit (ventana fija, persistente en Postgres)
create or replace function public.check_rate_limit(p_key text, p_max integer, p_window interval)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  secs   double precision := extract(epoch from p_window);
  wstart timestamptz := to_timestamp(floor(extract(epoch from now()) / secs) * secs);
  n      integer;
begin
  insert into public.rate_limits (key, window_start, hits)
  values (p_key, wstart, 1)
  on conflict (key, window_start) do update set hits = public.rate_limits.hits + 1
  returning hits into n;
  delete from public.rate_limits where window_start < now() - interval '1 day';
  return n <= p_max;
end $$;

revoke all on function public.check_rate_limit(text, integer, interval) from public, anon, authenticated;
grant execute on function public.check_rate_limit(text, integer, interval) to service_role;

-- ---------------------------------------------------------------- incidents: inserción
create or replace function public.incidents_before_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.radicado    := public.generate_radicado();
  new.received_at := now();
  new.updated_at  := now();
  new.status      := 'RECIBIDO';
  new.assigned_to := null;
  new.duplicate_of := null;
  new.closure_reason := null;
  if new.source <> 'INSTITUCIONAL' then
    new.verification_level := 'REPORTE_CIUDADANO';
  end if;
  new.out_of_scope := not public.in_territorial_scope(new.location);
  new.quadrant_id  := case when new.out_of_scope then null else public.assign_quadrant(new.location) end;
  return new;
end $$;

create trigger incidents_before_insert before insert on public.incidents
  for each row execute function public.incidents_before_insert();

create or replace function public.incidents_after_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.incident_history (incident_id, actor_id, action, old_status, new_status, note, is_internal, metadata)
  values (new.id, new.reporter_id, 'CREADO', null, new.status, 'Reporte recibido', false,
          jsonb_build_object('quadrant_id', new.quadrant_id, 'out_of_scope', new.out_of_scope));
  return new;
end $$;

create trigger incidents_after_insert after insert on public.incidents
  for each row execute function public.incidents_after_insert();

-- ---------------------------------------------------------------- incidents: transiciones de estado
create or replace function public.is_valid_transition(p_from public.incident_status, p_to public.incident_status)
returns boolean language sql immutable as $$
  select p_from = p_to or (p_from, p_to) in (
    ('RECIBIDO','EN_REVISION'), ('RECIBIDO','ASIGNADO'), ('RECIBIDO','NO_PROCEDE'),
    ('EN_REVISION','ASIGNADO'), ('EN_REVISION','NO_PROCEDE'),
    ('ASIGNADO','EN_ATENCION'), ('ASIGNADO','EN_REVISION'), ('ASIGNADO','NO_PROCEDE'),
    ('EN_ATENCION','CERRADO'), ('EN_ATENCION','ASIGNADO')
  );
$$;

create or replace function public.incidents_before_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.radicado is distinct from old.radicado
     or new.received_at is distinct from old.received_at
     or new.source is distinct from old.source
     or new.reporter_id is distinct from old.reporter_id
     or new.anon_token_hash is distinct from old.anon_token_hash
     or new.occurred_at is distinct from old.occurred_at
     or new.location::text is distinct from old.location::text then
    raise exception 'Campo inmutable del reporte' using errcode = 'P0001';
  end if;

  if not public.is_valid_transition(old.status, new.status) then
    raise exception 'Transición de estado no permitida: % → %', old.status, new.status using errcode = 'P0001';
  end if;

  if new.status in ('CERRADO','NO_PROCEDE') and new.status <> old.status
     and coalesce(btrim(new.closure_reason), '') = '' then
    raise exception 'El estado % exige motivo', new.status using errcode = 'P0001';
  end if;

  new.updated_at := now();
  return new;
end $$;

create trigger incidents_before_update before update on public.incidents
  for each row execute function public.incidents_before_update();

create or replace function public.incidents_after_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if new.status <> old.status then
    insert into public.incident_history (incident_id, actor_id, action, old_status, new_status, note, is_internal)
    values (new.id, actor,
            case when new.status in ('CERRADO','NO_PROCEDE') then 'CIERRE' else 'CAMBIO_ESTADO' end,
            old.status, new.status,
            case when new.status in ('CERRADO','NO_PROCEDE') then new.closure_reason end,
            false);
  end if;
  if new.quadrant_id is distinct from old.quadrant_id or new.assigned_to is distinct from old.assigned_to then
    insert into public.incident_history (incident_id, actor_id, action, is_internal, metadata)
    values (new.id, actor,
            case when old.quadrant_id is null and old.assigned_to is null then 'ASIGNACION' else 'REASIGNACION' end,
            true,
            jsonb_build_object('from_quadrant', old.quadrant_id, 'to_quadrant', new.quadrant_id,
                               'from_user', old.assigned_to, 'to_user', new.assigned_to));
  end if;
  if new.category_id <> old.category_id then
    insert into public.incident_history (incident_id, actor_id, action, is_internal, metadata)
    values (new.id, actor, 'CLASIFICACION', true,
            jsonb_build_object('from', old.category_id, 'to', new.category_id));
  end if;
  if new.priority <> old.priority then
    insert into public.incident_history (incident_id, actor_id, action, is_internal, metadata)
    values (new.id, actor, 'PRIORIDAD', true, jsonb_build_object('from', old.priority, 'to', new.priority));
  end if;
  if new.verification_level <> old.verification_level then
    insert into public.incident_history (incident_id, actor_id, action, is_internal, metadata)
    values (new.id, actor, 'VERIFICACION', true,
            jsonb_build_object('from', old.verification_level, 'to', new.verification_level));
  end if;
  if new.duplicate_of is distinct from old.duplicate_of then
    insert into public.incident_history (incident_id, actor_id, action, is_internal, metadata)
    values (new.id, actor, 'DUPLICADO', true, jsonb_build_object('duplicate_of', new.duplicate_of));
  end if;
  return new;
end $$;

create trigger incidents_after_update after update on public.incidents
  for each row execute function public.incidents_after_update();

-- ---------------------------------------------------------------- mensajes institucionales → historial visible
create or replace function public.institutional_messages_after_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.incident_history (incident_id, actor_id, action, note, is_internal)
  values (new.incident_id, new.author_id, 'MENSAJE_CIUDADANO', new.body, false);
  return new;
end $$;

create trigger institutional_messages_after_insert after insert on public.institutional_messages
  for each row execute function public.institutional_messages_after_insert();

-- ---------------------------------------------------------------- inmutabilidad de historial y auditoría
create or replace function public.prevent_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'Registro histórico inalterable (%)', tg_table_name using errcode = 'P0001';
end $$;

create trigger incident_history_immutable before update or delete on public.incident_history
  for each row execute function public.prevent_mutation();
create trigger incident_history_no_truncate before truncate on public.incident_history
  for each statement execute function public.prevent_mutation();
create trigger audit_logs_immutable before update or delete on public.audit_logs
  for each row execute function public.prevent_mutation();
create trigger audit_logs_no_truncate before truncate on public.audit_logs
  for each statement execute function public.prevent_mutation();
create trigger institutional_messages_immutable before update or delete on public.institutional_messages
  for each row execute function public.prevent_mutation();

-- ---------------------------------------------------------------- perfil automático al registrarse (siempre ciudadano)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, role_code)
  values (new.id, nullif(btrim(new.raw_user_meta_data->>'full_name'), ''), 'ciudadano')
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
