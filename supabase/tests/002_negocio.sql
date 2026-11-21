-- Reglas de negocio: radicado, sello de servidor, transiciones, inmutabilidad, rate limit, perfiles
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

-- Datos de prueba
insert into public.quadrants (id, code, name, boundary, boundary_source) values
  ('00000000-0000-0000-0000-0000000000a1', 'TEST-Q1', 'Cuadrante prueba',
   'SRID=4326;MULTIPOLYGON(((-73.13 7.11,-73.11 7.11,-73.11 7.13,-73.13 7.13,-73.13 7.11)))'::extensions.geography,
   'prueba-unitaria');

insert into public.incidents (id, radicado, category_id, description, occurred_at, received_at,
                              location, source, anon_token_hash, status, verification_level, quadrant_id)
select '00000000-0000-0000-0000-0000000000c1'::uuid, 'MANIPULADO', id,
       'Descripción suficientemente larga', now() - interval '1 hour', '2000-01-01',
       'SRID=4326;POINT(-73.12 7.12)', 'APP_ANONIMO', 'hash', 'CERRADO', 'DELITO_CONFIRMADO', null
from public.categories where name = 'Hurto';

-- 1-6: el servidor fija los campos sensibles
select matches((select radicado from public.incidents where id = '00000000-0000-0000-0000-0000000000c1'),
  '^BGA-\d{4}-\d{6}$', 'radicado con formato BGA-AAAA-NNNNNN');
select ok((select received_at > now() - interval '1 minute' from public.incidents where id = '00000000-0000-0000-0000-0000000000c1'),
  'received_at del cliente ignorado');
select is((select status::text from public.incidents where id = '00000000-0000-0000-0000-0000000000c1'),
  'RECIBIDO', 'status inicial forzado a RECIBIDO');
select is((select verification_level::text from public.incidents where id = '00000000-0000-0000-0000-0000000000c1'),
  'REPORTE_CIUDADANO', 'nivel inicial forzado a REPORTE_CIUDADANO');
select is((select quadrant_id from public.incidents where id = '00000000-0000-0000-0000-0000000000c1'),
  '00000000-0000-0000-0000-0000000000a1'::uuid, 'cuadrante asignado por polígono');
select is((select count(*)::int from public.incident_history
           where incident_id = '00000000-0000-0000-0000-0000000000c1' and action = 'CREADO' and not is_internal),
  1, 'historial CREADO visible al ciudadano');

-- 7: fuera del ámbito territorial se marca, no se elimina (RB-07)
insert into public.incidents (id, radicado, category_id, description, occurred_at, location, source, anon_token_hash)
select '00000000-0000-0000-0000-0000000000c2'::uuid, 'x', id, 'Reporte fuera del municipio', now(),
       'SRID=4326;POINT(-74.07 4.71)', 'APP_ANONIMO', 'hash2'
from public.categories where name = 'Hurto';
select ok((select out_of_scope and quadrant_id is null from public.incidents where id = '00000000-0000-0000-0000-0000000000c2'),
  'fuera de ámbito marcado y sin cuadrante (cola manual)');

-- 8-11: transiciones
select lives_ok($$update public.incidents set status = 'EN_REVISION' where id = '00000000-0000-0000-0000-0000000000c1'$$,
  'RECIBIDO → EN_REVISION permitido');
select throws_ok($$update public.incidents set status = 'EN_ATENCION' where id = '00000000-0000-0000-0000-0000000000c1'$$,
  'P0001', null, 'EN_REVISION → EN_ATENCION rechazado');
select throws_ok($$update public.incidents set status = 'NO_PROCEDE' where id = '00000000-0000-0000-0000-0000000000c1'$$,
  'P0001', null, 'NO_PROCEDE sin motivo rechazado');
select lives_ok($$update public.incidents set status = 'NO_PROCEDE', closure_reason = 'Duplicado de otro radicado'
                  where id = '00000000-0000-0000-0000-0000000000c1'$$, 'NO_PROCEDE con motivo permitido');
select throws_ok($$update public.incidents set status = 'EN_REVISION' where id = '00000000-0000-0000-0000-0000000000c1'$$,
  'P0001', null, 'estado terminal no se reabre');

-- 12: campos inmutables
select throws_ok($$update public.incidents set received_at = now() - interval '3 days' where id = '00000000-0000-0000-0000-0000000000c2'$$,
  'P0001', null, 'received_at inmutable');

-- 13-14: historial y auditoría inalterables
select throws_ok($$update public.incident_history set note = 'editado'$$, 'P0001', null, 'historial no se edita');
insert into public.audit_logs (action, entity) values ('PRUEBA', 'test');
select throws_ok($$delete from public.audit_logs$$, 'P0001', null, 'auditoría no se borra');

-- 15: rate limit
select is((select array_agg(public.check_rate_limit('test-key', 2, interval '1 hour')) from generate_series(1,3)),
  array[true, true, false], 'rate limit bloquea el intento máx+1');

-- 16-17: alta en auth crea perfil ciudadano (aunque el metadato pida otro rol)
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'nuevo@test.co', '{"full_name":"Ana Prueba","role_code":"administrador"}', '{}', now(), now());
select is((select role_code from public.profiles where id = '00000000-0000-0000-0000-0000000000b1'),
  'ciudadano', 'perfil creado como ciudadano, ignora rol del metadato');
select is((select full_name from public.profiles where id = '00000000-0000-0000-0000-0000000000b1'),
  'Ana Prueba', 'nombre tomado del metadato');

select * from finish();
rollback;
