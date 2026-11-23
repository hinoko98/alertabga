# Levanta el entorno local completo de AlertaBGA (Windows PowerShell).
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\iniciar-entorno.ps1 [-SinWeb]
param([switch]$SinWeb)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "1/5 Docker..." -ForegroundColor Cyan
docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "   Iniciando Docker Desktop (espere ~1 min)..."
  Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  do { Start-Sleep 5; docker info --format '{{.ServerVersion}}' *> $null } until ($LASTEXITCODE -eq 0)
}

Write-Host "2/5 Supabase local (personal del panel, categorías, almacenamiento de evidencias)..." -ForegroundColor Cyan
npx --yes supabase@2 start | Out-Null
Write-Host "   Studio: http://127.0.0.1:54323"
Write-Host "   Usuarios de prueba del panel web:"
& "$PSScriptRoot\usuarios-demo.ps1"

Write-Host "3/5 Backend en Docker: MongoDB (27018) + API FastAPI (8000)..." -ForegroundColor Cyan
docker compose up -d --build
do { Start-Sleep 2; $ok = try { (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/api/py/health -TimeoutSec 2).StatusCode -eq 200 } catch { $false } } until ($ok)
Write-Host "   API: http://127.0.0.1:8000/api/py/docs"

Write-Host "4/5 App móvil: abra el emulador y ejecute 'cd mobile; flutter run' (no requiere más configuración)." -ForegroundColor Cyan

if (-not $SinWeb) {
  Write-Host "5/5 Dashboard Next.js en http://localhost:4000 ..." -ForegroundColor Cyan
  Start-Process -FilePath "npm.cmd" -ArgumentList "run","dev" -WorkingDirectory "$root\web"
  # El modo desarrollo compila cada página la primera vez que se pide (10-25 s); se hace aquí para que
  # el navegador abra rápido.
  Write-Host "   Compilando páginas por adelantado..."
  do { Start-Sleep 2; $up = try { (Invoke-WebRequest -UseBasicParsing http://localhost:4000/login -TimeoutSec 120).StatusCode -eq 200 } catch { $false } } until ($up)
  try { Invoke-WebRequest -UseBasicParsing http://localhost:4000/ -MaximumRedirection 0 -TimeoutSec 120 | Out-Null } catch {}
}

Write-Host "`nListo. Web: http://localhost:4000 · App: cd mobile; flutter run" -ForegroundColor Green
