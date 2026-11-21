-- AlertaBGA · Tablas núcleo (operación). Todas las fechas en timestamptz (UTC); la UI muestra America/Bogota.

-- ---------------------------------------------------------------- roles
create table public.roles (
  code        text primary key check (code in ('ciudadano','operador','supervisor','administrador')),
  name        text not null,
  description text not null default '',
  is_staff    boolean not null default false
);

-- ---------------------------------------------------------------- profiles (1:1 con auth.users)
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text check (char_length(full_name) <= 120),
  phone       text check (phone ~ '^\+?[0-9 ]{7,20}$'),
  role_code   text not null default 'ciudadano' references public.roles (code),
  active      boolean not null default true,
  notify_status_changes boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index profiles_role_idx on public.profiles (role_code);

-- ---------------------------------------------------------------- quadrants
-- boundary nulo = sin polígono oficial cargado → asignación manual (no se inventan límites)
create table public.quadrants (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique check (char_length(code) between 1 and 40),
  name            text not null,
  commune         text,
  boundary        extensions.geography(MultiPolygon, 4326),
  boundary_source text,
  staff_count     integer check (staff_count >= 0),
  contact_ref     text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint boundary_requires_source check (boundary is null or boundary_source is not null)
);
create index quadrants_boundary_gix on public.quadrants using gist (boundary);

-- Pertenencia de personal a cuadrantes (operador: su cuadrante; supervisor: su ámbito)
create table public.profile_quadrants (
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  quadrant_id uuid not null references public.quadrants (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (profile_id, quadrant_id)
);
create index profile_quadrants_quadrant_idx on public.profile_quadrants (quadrant_id);

-- ---------------------------------------------------------------- categories
create table public.categories (
  id               uuid primary key default gen_random_uuid(),
  name             text not null unique check (char_length(name) between 2 and 80),
  description      text not null default '',
  icon             text not null default 'alert-triangle',
  color            text not null default '#F59E0B' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  severity_default smallint not null default 3 check (severity_default between 1 and 5),
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------- incidents
create sequence public.incident_radicado_seq;

create table public.incidents (
  id                 uuid primary key default gen_random_uuid(),
  radicado           text not null unique,
  category_id        uuid not null references public.categories (id),
  description        text not null check (char_length(description) between 10 and 2000),
  additional_info    text check (char_length(additional_info) <= 1000),
  occurred_at        timestamptz not null,
  received_at        timestamptz not null default now(),
  location           extensions.geography(Point, 4326) not null,
  accuracy_m         numeric(8,2) check (accuracy_m >= 0),
  location_manual    boolean not null default false,
  address_text       text check (char_length(address_text) <= 200),
  barrio             text,
  comuna             text,
  status             public.incident_status not null default 'RECIBIDO',
  priority           public.incident_priority not null default 'MEDIA',
  verification_level public.verification_level not null default 'REPORTE_CIUDADANO',
  source             public.report_source not null,
  reporter_id        uuid references public.profiles (id) on delete set null,
  anon_token_hash    text,
  quadrant_id        uuid references public.quadrants (id),
  assigned_to        uuid references public.profiles (id),
  duplicate_of       uuid references public.incidents (id),
  out_of_scope       boolean not null default false,
  closure_reason     text check (char_length(closure_reason) <= 1000),
  updated_at         timestamptz not null default now(),
  constraint occurred_not_future check (occurred_at <= received_at + interval '5 minutes'),
  constraint anon_coherente check (
    (source = 'APP_ANONIMO' and reporter_id is null and anon_token_hash is not null)
    or (source = 'APP_AUTENTICADO' and anon_token_hash is null)
    or (source = 'INSTITUCIONAL' and anon_token_hash is null)
  )
);
create index incidents_location_gix   on public.incidents using gist (location);
create index incidents_received_idx   on public.incidents (received_at desc);
create index incidents_status_idx     on public.incidents (status);
create index incidents_category_idx   on public.incidents (category_id);
create index incidents_quadrant_idx   on public.incidents (quadrant_id);
create index incidents_reporter_idx   on public.incidents (reporter_id);
create index incidents_assigned_idx   on public.incidents (assigned_to);

-- ---------------------------------------------------------------- evidence (metadatos; el archivo vive en R2)
create table public.evidence (
  id              uuid primary key default gen_random_uuid(),
  incident_id     uuid not null references public.incidents (id) on delete cascade,
  storage_key     text not null unique,
  mime_type       text not null check (mime_type in ('image/jpeg','image/png','image/webp')),
  size_bytes      integer not null check (size_bytes > 0 and size_bytes <= 5242880),
  checksum_sha256 text,
  status          public.evidence_status not null default 'PENDIENTE',
  uploaded_by     uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  confirmed_at    timestamptz,
  retention_until timestamptz
);
create index evidence_incident_idx on public.evidence (incident_id);

-- ---------------------------------------------------------------- assignments
create table public.assignments (
  id          uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.incidents (id) on delete cascade,
  quadrant_id uuid references public.quadrants (id),
  assigned_to uuid references public.profiles (id),
  assigned_by uuid references public.profiles (id),
  reason      text check (char_length(reason) <= 500),
  assigned_at timestamptz not null default now(),
  ended_at    timestamptz,
  outcome     text check (char_length(outcome) <= 1000),
  constraint assignment_target check (quadrant_id is not null or assigned_to is not null)
);
create index assignments_incident_idx on public.assignments (incident_id);
create index assignments_quadrant_idx on public.assignments (quadrant_id);

-- ---------------------------------------------------------------- incident_history (solo inserción)
create table public.incident_history (
  id          bigint generated always as identity primary key,
  incident_id uuid not null references public.incidents (id) on delete cascade,
  actor_id    uuid references public.profiles (id) on delete set null,
  action      text not null check (action in (
                'CREADO','CAMBIO_ESTADO','CLASIFICACION','ASIGNACION','REASIGNACION',
                'NOTA_INTERNA','MENSAJE_CIUDADANO','PRIORIDAD','VERIFICACION','DUPLICADO','CIERRE')),
  old_status  public.incident_status,
  new_status  public.incident_status,
  note        text check (char_length(note) <= 2000),
  is_internal boolean not null default true,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index incident_history_incident_idx on public.incident_history (incident_id, created_at);

-- ---------------------------------------------------------------- institutional_messages (visibles al ciudadano)
create table public.institutional_messages (
  id          uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.incidents (id) on delete cascade,
  author_id   uuid references public.profiles (id) on delete set null,
  body        text not null check (char_length(body) between 2 and 2000),
  created_at  timestamptz not null default now()
);
create index institutional_messages_incident_idx on public.institutional_messages (incident_id, created_at);

-- ---------------------------------------------------------------- notifications
create table public.notifications (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles (id) on delete cascade,
  incident_id     uuid references public.incidents (id) on delete cascade,
  channel         text not null check (channel in ('IN_APP','PUSH')),
  template        text not null,
  payload         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz,
  read_at         timestamptz,
  delivery_status text not null default 'PENDIENTE' check (delivery_status in ('PENDIENTE','ENVIADA','FALLIDA'))
);
create index notifications_profile_idx on public.notifications (profile_id, created_at desc);

-- ---------------------------------------------------------------- audit_logs (solo inserción)
create table public.audit_logs (
  id          bigint generated always as identity primary key,
  actor_id    uuid,
  actor_role  text,
  action      text not null,
  entity      text not null,
  entity_id   text,
  metadata    jsonb not null default '{}'::jsonb,
  ip_hash     text,
  created_at  timestamptz not null default now()
);
create index audit_logs_entity_idx on public.audit_logs (entity, entity_id);
create index audit_logs_created_idx on public.audit_logs (created_at desc);

-- ---------------------------------------------------------------- app_settings
create table public.app_settings (
  key         text primary key,
  value       jsonb not null,
  description text not null default '',
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------- rate_limits (anti-abuso serverless)
create table public.rate_limits (
  key          text not null,
  window_start timestamptz not null,
  hits         integer not null default 0,
  primary key (key, window_start)
);
