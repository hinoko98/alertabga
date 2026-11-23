-- AlertaBGA · Datos semilla de configuración (no son datos operativos simulados)

insert into public.roles (code, name, description, is_staff) values
  ('ciudadano',     'Ciudadano',     'Reporta incidentes y consulta sus reportes', false),
  ('operador',      'Operador',      'Gestiona reportes de su cuadrante', true),
  ('supervisor',    'Supervisor',    'Supervisa cuadrantes, operadores y tiempos', true),
  ('administrador', 'Administrador', 'Configuración institucional y usuarios', true)
on conflict (code) do nothing;

-- Catálogo inicial aprobado. Otras categorías las agrega el administrador desde el dashboard.
insert into public.categories (name, description, icon, color, severity_default) values
  ('Hurto',              'Apropiación de bienes sin violencia directa contra la persona', 'wallet',  '#F59E0B', 3),
  ('Robo de vehículos',  'Hurto de automotores, motocicletas o bicicletas',               'car',     '#EF4444', 4),
  ('Riñas y agresiones', 'Peleas, agresiones físicas o alteraciones a la convivencia',    'users',   '#8B5CF6', 3)
on conflict (name) do nothing;

-- Ámbito territorial: caja envolvente del municipio de Bucaramanga (aproximación operativa, no límite oficial).
-- Se reemplaza por el polígono oficial cuando la entidad lo suministre.
insert into public.app_settings (key, value, description) values
  ('territorial_scope',
   '{"type":"bbox","min_lat":7.03,"max_lat":7.25,"min_lon":-73.20,"max_lon":-73.03,"official":false}',
   'Ámbito territorial de validación de reportes'),
  ('evidence_limits',
   '{"max_bytes":5242880,"max_files":3,"mime":["image/jpeg","image/png","image/webp"]}',
   'Límites de evidencias fotográficas'),
  ('rate_limit_reports',
   '{"max":5,"window_minutes":60}',
   'Máximo de reportes por dispositivo/IP por ventana')
on conflict (key) do nothing;

-- SOLO LOCAL: bucket privado que emula Cloudflare R2 vía la interfaz S3 de Supabase Storage.
-- En producción las evidencias van a R2 (ver docs/configuracion/variables-entorno.md).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('alertabga-evidencias', 'alertabga-evidencias', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
