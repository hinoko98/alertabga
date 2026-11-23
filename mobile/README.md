# AlertaBGA — app ciudadana (Flutter)

Reporte ciudadano de incidentes de seguridad en Bucaramanga. La app habla **solo** con la API AlertaBGA;
no contiene claves de bases de datos (ADR 0003).

## Ejecutar

Con el backend arriba (`docker compose up -d` en la raíz, o `scripts\iniciar-entorno.ps1`) y un emulador abierto:

```powershell
flutter run
```

Nada más: en modo debug la app usa `http://10.0.2.2:8000/api/py` (el PC visto desde el emulador) y las fotos
se suben con URLs firmadas para ese mismo host.

### Otros destinos
| Caso | Comando |
|---|---|
| Teléfono físico por USB | `adb reverse tcp:8000 tcp:8000; adb reverse tcp:54321 tcp:54321` y `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/py` |
| Teléfono en la misma red Wi-Fi | `flutter run --dart-define=API_BASE_URL=http://<IP-del-PC>:8000/api/py` (exponga los puertos en el firewall) |
| Release / producción | `flutter build apk --release --dart-define=API_BASE_URL=https://<dominio>/api/py` (obligatorio en release) |

## Pruebas
```powershell
flutter analyze
flutter test
```
