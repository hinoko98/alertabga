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

Write-Host "3/5 Backend en Docker: MongoDB (27018) + API FastAPI (8000)..." -ForegroundColor Cyan
docker compose up -d --build
do { Start-Sleep 2; $ok = try { (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/api/py/health -TimeoutSec 2).StatusCode -eq 200 } catch { $false } } until ($ok)
Write-Host "   API: http://127.0.0.1:8000/api/py/docs"

Write-Host "4/5 Emulador / teléfono Android (adb reverse para las URL firmadas de fotos)..." -ForegroundColor Cyan
if (Get-Command adb -ErrorAction SilentlyContinue) {
  $devices = adb devices | Select-String "	device$"
  if ($devices) {
    adb reverse tcp:54321 tcp:54321 | Out-Null
    adb reverse tcp:8000 tcp:8000 | Out-Null
    Write-Host "   Listo para $($devices.Count) dispositivo(s)."
  } else {
    Write-Host "   Sin dispositivo conectado: abra el emulador y vuelva a ejecutar este script (o: adb reverse tcp:54321 tcp:54321)."
  }
}

if (-not $SinWeb) {
  Write-Host "5/5 Dashboard Next.js en http://localhost:4000 ..." -ForegroundColor Cyan
  Start-Process -FilePath "npm.cmd" -ArgumentList "run","dev","--","-p","4000" -WorkingDirectory "$root\web"
}

Write-Host "`nListo. Web: http://localhost:4000 · App: cd mobile; flutter run --dart-define-from-file=env.json" -ForegroundColor Green
