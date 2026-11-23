# Ejecuta todas las pruebas automatizadas de AlertaBGA y muestra un resumen.
# Requiere el entorno levantado (scripts\iniciar-entorno.ps1) para las pruebas de base de datos.
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\verificar-todo.ps1
$root = Split-Path -Parent $PSScriptRoot
$resultados = [ordered]@{}

function Probar($nombre, $dir, [scriptblock]$cmd) {
  Write-Host "`n=== $nombre ===" -ForegroundColor Cyan
  Push-Location $dir
  & $cmd
  $resultados[$nombre] = if ($LASTEXITCODE -eq 0) { "OK" } else { "FALLA" }
  Pop-Location
}

Probar "Base de datos (pgTAP: esquema, negocio, RLS, privilegios)" $root { npx --yes supabase@2 test db }
Probar "API FastAPI (pytest)"             "$root\web"       { .\.venv\Scripts\python -m pytest }
Probar "Dashboard (lint)"                 "$root\web"       { npm run lint }
Probar "Dashboard (tipos TypeScript)"     "$root\web"       { npx tsc --noEmit }
Probar "ETL PySpark (pytest)"             "$root\analytics" { .\.venv\Scripts\python -m pytest }
Probar "App móvil (flutter analyze)"      "$root\mobile"    { flutter analyze }
Probar "App móvil (flutter test)"         "$root\mobile"    { flutter test }
Probar "E2E backend (API + MongoDB + S3)"  "$root\web"       { .\.venv\Scripts\python scripts\verificar_reportes.py }

Write-Host "`n===== RESUMEN =====" -ForegroundColor Yellow
$resultados.GetEnumerator() | ForEach-Object {
  $color = if ($_.Value -eq "OK") { "Green" } else { "Red" }
  Write-Host ("{0,-60} {1}" -f $_.Key, $_.Value) -ForegroundColor $color
}
if ($resultados.Values -contains "FALLA") { exit 1 }
