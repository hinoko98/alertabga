-- Funciones internas no deben ser invocables por clientes vía RPC (PostgREST /rpc/*)
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

set local role anon;
select throws_ok($$select public.generate_radicado()$$, '42501', null, 'anon no genera radicados');
select throws_ok($$select public.assign_quadrant('SRID=4326;POINT(-73.12 7.12)'::extensions.geography)$$, '42501', null,
  'anon no consulta asignación de cuadrantes');
select throws_ok($$select public.in_territorial_scope('SRID=4326;POINT(-73.12 7.12)'::extensions.geography)$$, '42501', null,
  'anon no consulta ámbito');
select throws_ok($$select public.check_rate_limit('x', 1, interval '1 hour')$$, '42501', null, 'anon no manipula rate limit');
reset role;

set local role authenticated;
select throws_ok($$select public.generate_radicado()$$, '42501', null, 'authenticated no genera radicados');
reset role;

set local role service_role;
select lives_ok($$select public.check_rate_limit('svc-test', 5, interval '1 hour')$$, 'service_role sí usa rate limit');
reset role;

select * from finish();
rollback;
