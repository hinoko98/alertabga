# Genera el APK de pruebas de AlertaBGA para instalar en un teléfono Android real conectado a la
# MISMA red Wi-Fi que este PC, y expone la API local en la red.
#
# Uso (desde la raíz del repositorio, con el entorno ya iniciado con scripts\iniciar-entorno.ps1):
#   powershell -ExecutionPolicy Bypass -File scripts\apk-pruebas.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\apk-pruebas.ps1 -Ip 192.168.1.4   # forzar IP
#   powershell -ExecutionPolicy Bypass -File scripts\apk-pruebas.ps1 -SoloRed          # no recompilar
#
# El APK queda en dist\AlertaBGA-pruebas.apk. Si la IP del PC cambia, vuelva a ejecutar el script.
param(
  [string]$Ip = "",
  [switch]$SoloRed
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 1. IP del PC en la red local (la interfaz que tiene puerta de enlace = Wi-Fi o cable)
if (-not $Ip) {
  $Ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
    Select-Object -First 1).IPv4Address.IPAddress
}
if (-not $Ip) { throw "No se encontró la IP local. Pásela con -Ip 192.168.x.x" }
$api = "http://${Ip}:8000/api/py"
Write-Host "1/4 IP del PC en la red: $Ip" -ForegroundColor Cyan

# 2. API escuchando en la red (no solo en 127.0.0.1)
Write-Host "2/4 Exponiendo la API en la red local (puerto 8000)..." -ForegroundColor Cyan
$env:API_BIND = "0.0.0.0"
docker compose up -d api | Out-Null
$ok = $false
foreach ($i in 1..20) {
  try { Invoke-RestMethod "$api/health" -TimeoutSec 3 | Out-Null; $ok = $true; break } catch { Start-Sleep -Seconds 1 }
}
if (-not $ok) { throw "La API no responde en $api. ¿Ejecutó scripts\iniciar-entorno.ps1?" }
try { Invoke-WebRequest "http://${Ip}:54321/storage/v1/version" -UseBasicParsing -TimeoutSec 3 | Out-Null }
catch { if (-not $_.Exception.Response) { throw "Supabase (54321) no responde en $Ip. Ejecute 'npx supabase start'." } }
Write-Host "   API: $api  ·  fotos: http://${Ip}:54321" -ForegroundColor Green

# 3. Firewall de Windows (solo se revisa; abrirlo requiere administrador)
$rule = Get-NetFirewallRule -DisplayName "AlertaBGA pruebas" -ErrorAction SilentlyContinue
if (-not $rule) {
  Write-Host "3/4 FALTA permitir los puertos en el firewall de Windows. Abra PowerShell COMO ADMINISTRADOR y ejecute UNA vez:" -ForegroundColor Yellow
  Write-Host '   New-NetFirewallRule -DisplayName "AlertaBGA pruebas" -Direction Inbound -Protocol TCP -LocalPort 8000,54321 -Profile Private -Action Allow' -ForegroundColor White
  Write-Host "   (la red Wi-Fi debe estar como 'Privada' en Configuración > Red e Internet)."
} else {
  Write-Host "3/4 Firewall: regla 'AlertaBGA pruebas' presente." -ForegroundColor Green
}

if ($SoloRed) { Write-Host "`nListo (sin recompilar el APK)." -ForegroundColor Green; exit 0 }

# 4. APK release apuntando a esta API
Write-Host "4/4 Compilando APK (2-5 min la primera vez)..." -ForegroundColor Cyan
Push-Location mobile
try {
  flutter build apk --release --dart-define=API_BASE_URL=$api
  if ($LASTEXITCODE -ne 0) { throw "Falló la compilación del APK" }
} finally { Pop-Location }
New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item mobile\build\app\outputs\flutter-apk\app-release.apk dist\AlertaBGA-pruebas.apk -Force
$mb = [math]::Round((Get-Item dist\AlertaBGA-pruebas.apk).Length / 1MB, 1)

Write-Host "`nListo: dist\AlertaBGA-pruebas.apk ($mb MB) -> API $api" -ForegroundColor Green
Write-Host "Instalar:"
Write-Host "  - Con cable USB (depuración USB activa):  adb install -r dist\AlertaBGA-pruebas.apk"
Write-Host "  - Sin cable: copie el archivo al teléfono y ábralo (permita 'instalar apps desconocidas')."
Write-Host "Comprobar desde el teléfono: abra $api/health en Chrome; debe responder {""status"":""ok""...}."
