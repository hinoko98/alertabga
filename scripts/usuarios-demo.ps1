# Deja los usuarios de PRUEBA del panel web en Supabase LOCAL con contraseñas conocidas (solo desarrollo).
# Idempotente: crea los que falten y restablece contraseña y rol de los existentes.
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\usuarios-demo.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root "web\.env.local"
$svc = (Select-String $envFile -Pattern '^SUPABASE_SERVICE_ROLE_KEY=(.*)').Matches[0].Groups[1].Value
if ($svc -notmatch '^ey') { throw "Este script es solo para Supabase local (web/.env.local)." }
$base = "http://127.0.0.1:54321/auth/v1/admin/users"
$h = @{ apikey = $svc; Authorization = "Bearer $svc" }

$usuarios = @(
  @{ Email = "admin.local@example.com";       Password = "Admin-Local-2026";  Rol = "administrador"; Nombre = "Administrador Local" },
  @{ Email = "supervisor.prueba@example.com"; Password = "Supervisor-2026";   Rol = "supervisor";    Nombre = "Supervisor Prueba" },
  @{ Email = "operador.prueba@example.com";   Password = "Operador-2026";     Rol = "operador";      Nombre = "Operador Prueba" },
  @{ Email = "ciudadano.prueba@example.com";  Password = "Clave-Segura-2026"; Rol = "ciudadano";     Nombre = "Ciudadano Prueba" }
)

$existentes = (Invoke-RestMethod -Uri "$base`?per_page=1000" -Headers $h).users
foreach ($u in $usuarios) {
  $actual = $existentes | Where-Object { $_.email -eq $u.Email } | Select-Object -First 1
  $body = @{ email = $u.Email; password = $u.Password; email_confirm = $true; user_metadata = @{ full_name = $u.Nombre } } | ConvertTo-Json
  if ($actual) {
    $id = $actual.id
    Invoke-RestMethod -Method Put -Uri "$base/$id" -Headers $h -ContentType "application/json" -Body $body | Out-Null
  } else {
    $id = (Invoke-RestMethod -Method Post -Uri $base -Headers $h -ContentType "application/json" -Body $body).id
  }
  docker exec supabase_db_alertabga psql -U postgres -tc "update public.profiles set role_code='$($u.Rol)', active=true, full_name='$($u.Nombre)' where id='$id';" | Out-Null
  Write-Host ("   {0,-14} {1,-32} {2}" -f $u.Rol, $u.Email, $u.Password)
}
