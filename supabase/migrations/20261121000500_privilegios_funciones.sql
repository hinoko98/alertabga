-- AlertaBGA · Cierra la exposición por RPC de funciones internas (security definer).
-- Postgres concede EXECUTE a PUBLIC por defecto y PostgREST las publicaría en /rpc/*.
-- Los triggers siguen funcionando: se ejecutan con los privilegios del dueño de la función.

revoke execute on function public.generate_radicado() from public, anon, authenticated;
revoke execute on function public.assign_quadrant(extensions.geography) from public, anon, authenticated;
revoke execute on function public.in_territorial_scope(extensions.geography) from public, anon, authenticated;

-- Funciones de trigger: no invocables directamente, se revocan por higiene.
revoke execute on function public.incidents_before_insert() from public, anon, authenticated;
revoke execute on function public.incidents_after_insert() from public, anon, authenticated;
revoke execute on function public.incidents_before_update() from public, anon, authenticated;
revoke execute on function public.incidents_after_update() from public, anon, authenticated;
revoke execute on function public.institutional_messages_after_insert() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

grant execute on function public.generate_radicado(), public.assign_quadrant(extensions.geography),
  public.in_territorial_scope(extensions.geography) to service_role;
