-- Políticas RLS por rol
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- ---------------------------------------------------------------- datos (como postgres)
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'opa@test.co',  '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sup@test.co',  '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ciu@test.co',  '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa04', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm@test.co',  '{}', '{}', now(), now());

update public.profiles set role_code = 'operador'      where id = '00000000-0000-0000-0000-00000000aa01';
update public.profiles set role_code = 'supervisor'    where id = '00000000-0000-0000-0000-00000000aa02';
update public.profiles set role_code = 'administrador' where id = '00000000-0000-0000-0000-00000000aa04';

insert into public.quadrants (id, code, name, boundary, boundary_source) values
  ('00000000-0000-0000-0000-0000000000a1', 'T-A', 'Cuadrante A',
   'SRID=4326;MULTIPOLYGON(((-73.13 7.11,-73.11 7.11,-73.11 7.13,-73.13 7.13,-73.13 7.11)))', 'prueba'),
  ('00000000-0000-0000-0000-0000000000b1', 'T-B', 'Cuadrante B',
   'SRID=4326;MULTIPOLYGON(((-73.10 7.11,-73.08 7.11,-73.08 7.13,-73.10 7.13,-73.10 7.11)))', 'prueba');

insert into public.profile_quadrants values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', now()),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000b1', now());

insert into public.incidents (id, radicado, category_id, description, occurred_at, location, source, anon_token_hash, reporter_id)
select v.id::uuid, 'x', c.id, 'Descripción del incidente', now(), v.loc::extensions.geography, v.src::public.report_source, v.h, v.rep::uuid
from public.categories c,
  (values
    ('00000000-0000-0000-0000-0000000000d1', 'SRID=4326;POINT(-73.12 7.12)', 'APP_ANONIMO',     'h1', null),
    ('00000000-0000-0000-0000-0000000000d2', 'SRID=4326;POINT(-73.09 7.12)', 'APP_ANONIMO',     'h2', null),
    ('00000000-0000-0000-0000-0000000000d3', 'SRID=4326;POINT(-73.14 7.08)', 'APP_ANONIMO',     'h3', null),
    ('00000000-0000-0000-0000-0000000000d4', 'SRID=4326;POINT(-73.12 7.12)', 'APP_AUTENTICADO', null, '00000000-0000-0000-0000-00000000aa03')
  ) as v(id, loc, src, h, rep)
where c.name = 'Hurto';

insert into public.incident_history (incident_id, action, note, is_internal)
values ('00000000-0000-0000-0000-0000000000d4', 'NOTA_INTERNA', 'nota reservada', true);
insert into public.audit_logs (action, entity) values ('PRUEBA', 'test');

-- ---------------------------------------------------------------- operador (cuadrante A)
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000aa01","role":"authenticated"}';

select is((select count(*)::int from public.incidents), 2, 'operador A ve solo los 2 incidentes de su cuadrante');
select is((select count(*)::int from public.incidents where id = '00000000-0000-0000-0000-0000000000d2'), 0,
  'operador A no ve incidente de B');
select results_eq($$with u as (update public.incidents set priority = 'ALTA'
                    where id = '00000000-0000-0000-0000-0000000000d2' returning 1) select count(*)::int from u$$,
  array[0], 'operador A no puede actualizar incidente de B');
select lives_ok($$insert into public.incident_history (incident_id, actor_id, action, note)
                  values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000aa01', 'NOTA_INTERNA', 'revisado')$$,
  'operador A registra nota interna en su cuadrante');
select is((select count(*)::int from public.audit_logs), 0, 'operador no lee auditoría');

-- ---------------------------------------------------------------- supervisor (cuadrante B + cola sin cuadrante)
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000aa02","role":"authenticated"}';
select results_eq($$select id from public.incidents order by id$$,
  array['00000000-0000-0000-0000-0000000000d2'::uuid, '00000000-0000-0000-0000-0000000000d3'::uuid],
  'supervisor ve su ámbito y la cola sin cuadrante');
select is((select count(*)::int from public.audit_logs), 1, 'supervisor lee auditoría');

-- ---------------------------------------------------------------- ciudadano
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000aa03","role":"authenticated"}';
select results_eq($$select id from public.incidents$$,
  array['00000000-0000-0000-0000-0000000000d4'::uuid], 'ciudadano ve solo su reporte');
select is((select count(*)::int from public.incident_history where is_internal), 0, 'ciudadano no ve notas internas');
select is((select count(*)::int from public.incident_history), 1, 'ciudadano ve su historial público');
select throws_ok($$insert into public.incidents (radicado, category_id, description, occurred_at, location, source, reporter_id)
                   select 'x', id, 'Intento directo de inserción', now(), 'SRID=4326;POINT(-73.12 7.12)', 'APP_AUTENTICADO',
                          '00000000-0000-0000-0000-00000000aa03' from public.categories limit 1$$,
  '42501', null, 'ciudadano no inserta incidentes directamente');
select throws_ok($$update public.profiles set role_code = 'administrador' where id = '00000000-0000-0000-0000-00000000aa03'$$,
  'P0001', null, 'ciudadano no puede elevar su rol');

-- ---------------------------------------------------------------- administrador
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000aa04","role":"authenticated"}';
select is((select count(*)::int from public.incidents), 4, 'administrador ve todo');

-- ---------------------------------------------------------------- anónimo (sin sesión)
reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select is((select count(*)::int from public.incidents), 0, 'anon no lee incidentes');
select is((select count(*)::int from public.categories), 3, 'anon lee categorías activas');
reset role;

select ok((select count(*) = 4 from pg_publication_tables where pubname = 'supabase_realtime'
           and tablename in ('incidents','assignments','institutional_messages','incident_history')),
  'tablas publicadas en Supabase Realtime');

select * from finish();
rollback;
