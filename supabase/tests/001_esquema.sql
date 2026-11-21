-- Prueba del esquema núcleo de AlertaBGA
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- 11 tablas mínimas del prompt + auxiliares
select has_table('public', 'profiles', 'existe profiles');
select has_table('public', 'roles', 'existe roles');
select has_table('public', 'categories', 'existe categories');
select has_table('public', 'incidents', 'existe incidents');
select has_table('public', 'quadrants', 'existe quadrants');
select has_table('public', 'evidence', 'existe evidence');
select has_table('public', 'assignments', 'existe assignments');
select has_table('public', 'incident_history', 'existe incident_history');
select has_table('public', 'institutional_messages', 'existe institutional_messages');
select has_table('public', 'notifications', 'existe notifications');
select has_table('public', 'audit_logs', 'existe audit_logs');
select has_table('public', 'profile_quadrants', 'existe profile_quadrants');
select has_table('public', 'app_settings', 'existe app_settings');
select has_table('public', 'rate_limits', 'existe rate_limits');

-- Geografía e índice espacial
select col_type_is('public', 'incidents', 'location', 'geography(Point,4326)', 'location es geography(Point,4326)');
select ok(
  exists (select 1 from pg_indexes where tablename = 'incidents' and indexdef ilike '%USING gist (location)%'),
  'índice GiST en incidents.location'
);

-- Enum de estados exacto
select enum_has_labels('public', 'incident_status',
  array['RECIBIDO','EN_REVISION','ASIGNADO','EN_ATENCION','CERRADO','NO_PROCEDE'], 'estados del incidente');
select enum_has_labels('public', 'verification_level',
  array['REPORTE_CIUDADANO','CASO_VERIFICADO','DELITO_CONFIRMADO'], 'niveles de verificación');

-- Semillas
select results_eq('select code from public.roles order by code',
  array['administrador','ciudadano','operador','supervisor']::text[], '4 roles');
select results_eq('select name from public.categories order by name',
  array['Hurto','Riñas y agresiones','Robo de vehículos']::text[], 'solo las 3 categorías aprobadas');

-- Radicado único y anónimo coherente
select col_is_unique('public', 'incidents', 'radicado', 'radicado único');
select col_is_null('public', 'incidents', 'reporter_id', 'reporter_id admite nulo (anónimo)');

select * from finish();
rollback;
