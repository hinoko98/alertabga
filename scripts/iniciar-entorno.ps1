# Levanta el entorno local completo de AlertaBGA (Windows PowerShell).
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\iniciar-entorno.ps1
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

Write-Host "2/5 Supabase local (Postgres+PostGIS, Auth, Realtime)..." -ForegroundColor Cyan
npx --yes supabase@2 start | Out-Null
Write-Host "   Studio: http://127.0.0.1:54323"

Write-Host "3/5 MongoDB (puerto 27018)..." -ForegroundColor Cyan
docker compose up -d | Out-Null

Write-Host "4/5 API FastAPI en http://127.0.0.1:8000 ..." -ForegroundColor Cyan
Start-Process -FilePath "$root\web\.venv\Scripts\python.exe" -ArgumentList "-m","uvicorn","api.index:app","--reload","--port","8000" -WorkingDirectory "$root\web"

Write-Host "5/5 Dashboard Next.js en http://localhost:4000 ..." -ForegroundColor Cyan
Start-Process -FilePath "npm.cmd" -ArgumentList "run","dev","--","-p","4000" -WorkingDirectory "$root\web"

Write-Host "`nListo. Abra http://localhost:4000 (docs API: http://localhost:4000/api/py/docs)" -ForegroundColor Green
