# Guía: cómo lanzar y probar AlertaBGA (Windows)

Estado actual: **Fase 0 y Fase 1** (infraestructura, autenticación, permisos y verificación de conexiones).
Las pantallas de reporte, mapa y bandeja llegan en las Fases 2 y 3. Hoy se prueba que todas las piezas están conectadas y seguras.

---

## 0. Requisitos (ya instalados en esta máquina)
Docker Desktop · Node 23 · Python 3.11 · Flutter 3.47 · Android SDK con emulador.

Si `flutter doctor` avisa de licencias de Android: `flutter doctor --android-licenses` (aceptar con `y`).

### Primera vez en otra máquina
```powershell
cd web;       python -m venv .venv; .\.venv\Scripts\pip install -r requirements.txt -r requirements-dev.txt; npm install; cd ..
cd analytics; python -m venv .venv; .\.venv\Scripts\pip install -r requirements.txt -r requirements-dev.txt; cd ..
cd mobile;    flutter pub get; cd ..
```
Luego cree `web\.env.local` desde `web\.env.example` con los valores que imprime `npx supabase@2 start`, y `mobile\env.json` desde `mobile\env.example.json`.

---

## 1. Levantar todo con un comando
```powershell
powershell -ExecutionPolicy Bypass -File scripts\iniciar-entorno.ps1
```
Inicia Docker (si hace falta), Supabase local, MongoDB (puerto 27018), la API FastAPI (:8000) y el dashboard (:4000).

| Servicio | URL |
|---|---|
| Dashboard web | http://localhost:4000 |
| Documentación interactiva de la API | http://localhost:4000/api/py/docs |
| Supabase Studio (ver tablas y usuarios) | http://127.0.0.1:54323 |
| Correos de prueba (recuperar contraseña) | http://127.0.0.1:54324 |

> El puerto 3000 está reservado por Windows/Hyper-V en esta máquina; por eso el dashboard usa el 4000.

## 2. Ejecutar todas las pruebas automáticas
```powershell
powershell -ExecutionPolicy Bypass -File scripts\verificar-todo.ps1
```
Debe terminar con 7 líneas **OK**:

| Suite | Qué comprueba |
|---|---|
| pgTAP (4 archivos) | Tablas e índices; radicado `BGA-AAAA-NNNNNN`; fecha de recepción fijada por el servidor; transiciones de estado; historial y auditoría inalterables; operador solo ve su cuadrante; ciudadano solo lo suyo; funciones internas no expuestas |
| API pytest (15) | JWT ausente, vencido o mal firmado → 401; roles; salud; endpoints de histórico |
| lint + tsc | Calidad y tipos del dashboard |
| ETL pytest (5) | Reconstrucción de coordenadas, limpieza y agregaciones |
| flutter analyze + test (4) | App móvil |

---

## 3. Probar el dashboard web (manual)

1. **Crear usuarios de prueba** (solo local):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\crear-usuario-local.ps1 -Email admin.local@example.com -Password "Admin-Local-2026" -Rol administrador -Nombre "Administrador Local"
   powershell -ExecutionPolicy Bypass -File scripts\crear-usuario-local.ps1 -Email ciudadano.prueba@example.com -Password "Clave-Segura-2026" -Rol ciudadano -Nombre "Ciudadano Prueba"
   ```
   (Si ya existen, el script responde que el correo está registrado. Es normal.)
2. Abra http://localhost:4000. Sin sesión, debe redirigir a **/login**.
3. Ingrese como **administrador**. Verá "Estado de la plataforma" con las tarjetas:
   - API Python, Autenticación (JWT → API), Supabase, MongoDB y Realtime en **Operativo**.
   - Cloudflare R2 en **Pendiente de configurar** (se completa al crear el bucket).
4. **Prueba de tiempo real:** con el panel abierto, en otra terminal:
   ```powershell
   cd web; node --env-file=.env.local scripts\verificar-realtime.mjs
   ```
   En "Eventos de incidentes recibidos en tiempo real" aparece un `INSERT` en pocos segundos. El script también confirma que un ciudadano ajeno **no** recibe el evento (RLS).
5. Cierre sesión e ingrese como **ciudadano**. Debe ver "Sin acceso al panel institucional".
6. **Histórico institucional** (con el token del admin), desde http://localhost:4000/api/py/docs → `GET /historico/resumen`. Devuelve dos fuentes etiquetadas:
   - `HISTORICO_GEORREFERENCIADO`, periodo 2010-2021, 127.754 registros
   - `OFICIAL_AGREGADO`, periodo 2016-01..2026-09, 268.995 registros

## 4. Probar la app móvil

### Opción A — Emulador (recomendada)
```powershell
flutter emulators                                   # lista: Pixel_7, flutter_emulator, ...
flutter emulators --launch Pixel_7
cd mobile
flutter run --dart-define-from-file=env.json        # r = hot reload, q = salir
```
`mobile\env.json` ya apunta a `10.0.2.2`, que es la dirección del PC visto desde el emulador.

### Opción B — Teléfono físico por USB
1. Active "Depuración USB" en el teléfono y conéctelo (`adb devices` debe listarlo).
2. Redirija los puertos al PC:
   ```powershell
   adb reverse tcp:8000 tcp:8000
   adb reverse tcp:54321 tcp:54321
   ```
3. Cree `mobile\env.phone.json` igual a `env.json`, pero con `127.0.0.1` en lugar de `10.0.2.2`, y ejecute:
   ```powershell
   cd mobile; flutter run --dart-define-from-file=env.phone.json
   ```

### Qué debe ver
Pantalla "Estado de conexión" con el escudo AlertaBGA:
- **API Python (FastAPI)**: Operativo · API operativa
- **Supabase (categorías públicas)**: Operativo · Hurto · Riñas y agresiones · Robo de vehículos

Deslice hacia abajo para reintentar. Si aparece "Configuración incompleta", faltó `--dart-define-from-file=env.json`.

### Instalar un APK sin `flutter run`
```powershell
cd mobile
flutter build apk --debug --dart-define-from-file=env.json
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

---

## 5. Recargar datos históricos (opcional)
```powershell
cd analytics
.\.venv\Scripts\python -m alertabga_etl.pipeline --mongo-uri mongodb://127.0.0.1:27018
```
Descarga de datos.gov.co a `data\raw\` (ignorado por git), limpia con PySpark y reemplaza los datos en MongoDB.

## 6. Problemas frecuentes
| Síntoma | Solución |
|---|---|
| `EACCES` al iniciar Next en 3000 | Use `npm run dev -- -p 4000` |
| Mongo no arranca en 27017 | Ya hay un MongoDB local en ese puerto; el proyecto usa 27018 |
| Build Android falla con "incremental caches" | Ya está resuelto con `kotlin.incremental=false`. Si persiste: `flutter clean` |
| Tarjeta Realtime en "Con fallas" | Revise que Supabase esté arriba (`npx supabase@2 status`) |
| Quiero empezar de cero la base local | `npx supabase@2 db reset` (borra usuarios y datos locales) |
| Detener todo | Cierre las ventanas de API/Next; `npx supabase@2 stop`; `docker compose down` |
