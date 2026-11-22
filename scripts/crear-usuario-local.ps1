# Crea un usuario de PRUEBA en Supabase LOCAL y le asigna rol (solo desarrollo).
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\crear-usuario-local.ps1 -Email op@example.com -Password "Clave-2026" -Rol operador -Nombre "Operador Prueba"
param(
  [Parameter(Mandatory)] [string]$Email,
  [Parameter(Mandatory)] [string]$Password,
  [ValidateSet("ciudadano","operador","supervisor","administrador")] [string]$Rol = "ciudadano",
  [string]$Nombre = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root "web\.env.local"
$svc = (Select-String $envFile -Pattern '^SUPABASE_SERVICE_ROLE_KEY=(.*)').Matches[0].Groups[1].Value
if ($svc -notmatch '^ey') { throw "Este script es solo para Supabase local (web/.env.local)." }

$body = @{ email = $Email; password = $Password; email_confirm = $true; user_metadata = @{ full_name = $Nombre } } | ConvertTo-Json
$u = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:54321/auth/v1/admin/users" `
  -Headers @{ apikey = $svc; Authorization = "Bearer $svc" } -ContentType "application/json" -Body $body

if ($Rol -ne "ciudadano") {
  docker exec supabase_db_alertabga psql -U postgres -tc "update public.profiles set role_code='$Rol' where id='$($u.id)';" | Out-Null
}
Write-Host "Usuario $Email creado con rol $Rol (id $($u.id))" -ForegroundColor Green
