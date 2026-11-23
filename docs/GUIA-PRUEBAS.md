# Guía: cómo lanzar y probar AlertaBGA (Windows)

Estado actual: **Fase 2 — app ciudadana** y **Fase 3 — panel institucional** completas.
- App: cuenta, reporte con GPS/mapa y fotos, reporte anónimo, seguimiento y emergencias.
- Panel: panel principal, mapa territorial con calor, bandeja, detalle con gestión de estados, estadísticas y administración.

**Arquitectura local (ADR 0003):**
| Pieza | Cómo corre | Datos |
|---|---|---|
| API FastAPI + MongoDB | **Docker** (`docker compose up -d --build`) | Cuentas ciudadanas, reportes, historial, evidencias, histórico oficial |
| Supabase local | Docker, vía `npx supabase@2 start` | Personal del panel, categorías, ajustes, almacenamiento S3 de fotos |
| Panel web Next.js | `npm run dev` en `web\` → http://localhost:4000 (fuera de Docker) | Supabase para el login del personal; la API para lo demás |
| App Android | `flutter run` en emulador o teléfono (no puede ir en Docker) | **Solo habla con la API**; no usa Supabase |

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
Luego cree `web\.env.local` desde `web\.env.example` con los valores que imprime `npx supabase@2 start`,. La app móvil no necesita archivo de configuración.

---

## 1. Levantar todo con un comando
```powershell
powershell -ExecutionPolicy Bypass -File scripts\iniciar-entorno.ps1
```
Inicia Docker (si hace falta), Supabase local, el backend en Docker (MongoDB :27018 + API :8000), deja listos los usuarios de prueba del panel y abre el dashboard (:4000) ya compilado. Con `-SinWeb` no abre el dashboard.

Solo el backend: `docker compose up -d --build` (requiere Supabase arriba para categorías y fotos). Registros: `docker compose logs -f api`.

| Servicio | URL |
|---|---|
| Dashboard web | http://localhost:4000 |
| Documentación interactiva de la API | http://localhost:4000/api/py/docs |
| Supabase Studio (ver tablas y usuarios) | http://127.0.0.1:54323 |
| Documentación de la API (directa) | http://127.0.0.1:8000/api/py/docs |
| Correos de prueba del **personal** (Supabase) | http://127.0.0.1:54324 |
| Código de recuperación de **ciudadanos** (local) | `docker compose logs api` (busque "Su código es") |

### Credenciales del panel web (solo local)
| Rol | Correo | Contraseña |
|---|---|---|
| Administrador | `admin.local@example.com` | `Admin-Local-2026` |
| Supervisor | `supervisor.prueba@example.com` | `Supervisor-2026` |
| Operador | `operador.prueba@example.com` | `Operador-2026` |
| Ciudadano (debe ver "Sin acceso") | `ciudadano.prueba@example.com` | `Clave-Segura-2026` |

Si alguna no funciona (p. ej. tras `npx supabase@2 db reset`): `powershell -ExecutionPolicy Bypass -File scripts\usuarios-demo.ps1`.

### Velocidad del panel
- `npm run dev` (desarrollo) compila cada página **la primera vez** que se abre: 10-25 s. Después, ~0,3 s. El script de arranque las compila por adelantado.
- `npm run preview` (compilación de producción, ~30 s una vez): todas las páginas cargan en menos de 0,3 s. Úselo para demostraciones.
- Abra **http://localhost:4000** (no la IP de red) para que la recarga en vivo funcione.

## 2. Ejecutar todas las pruebas automáticas
```powershell
powershell -ExecutionPolicy Bypass -File scripts\verificar-todo.ps1
```
Debe terminar con 8 líneas **OK** (la última es el E2E del backend; necesita el entorno levantado):

| Suite | Qué comprueba |
|---|---|
| pgTAP (4 archivos) | Tablas e índices; radicado `BGA-AAAA-NNNNNN`; fecha de recepción fijada por el servidor; transiciones de estado; historial y auditoría inalterables; operador solo ve su cuadrante; ciudadano solo lo suyo; funciones internas no expuestas |
| API pytest (86) | Cuentas ciudadanas (scrypt, sesiones rotativas, recuperación con código, sin revelar correos); reportes y anónimos (token solo como hash, 404 uniforme, rate limit, timeline sin notas internas); evidencias (máx. 3, HEAD, rechazo); repositorio Mongo; JWT del personal; histórico |
| lint + tsc | Calidad y tipos del dashboard |
| ETL pytest (5) | Reconstrucción de coordenadas, limpieza y agregaciones |
| flutter analyze + test (41) | Validación del borrador, ámbito territorial, estados, controlador (sin doble envío), sesión y renovación de token, pantallas |
| E2E backend | `web\scripts\verificar_reportes.py`: registro → reporte → foto al S3 local → seguimiento sin notas internas, todo en MongoDB |

---

## 3. Probar el panel web (manual)

**Datos de demostración** (opcional, para ver el panel con información):
```powershell
cd web; .\.venv\Scripts\python scripts\sembrar_demo.py          # 80 reportes BGA-DEMO-* de los últimos 45 días
.\.venv\Scripts\python scripts\sembrar_demo.py --borrar             # quitarlos
```

1. Abra http://localhost:4000. Sin sesión redirige a **/login**. Use las credenciales de la tabla de arriba.
2. **Panel principal** (administrador): abiertos, recibidos hoy, sin asignar, asignados a usted, prioridad alta, serie de 14 días, estados, últimos reportes y categorías. Se actualiza solo cada 20 s.
3. **Bandeja de incidentes**: pestañas Abiertos · Sin asignar · Asignados a mí · Cerrados · Todos; búsqueda por radicado o texto, filtros de estado, categoría, prioridad y fechas; paginación. Supervisor y administrador ven **Exportar CSV** (sin datos personales).
4. **Detalle** (clic en un radicado): descripción, ubicación en el mapa, fotos, reportante (o "anónimo"), historial completo marcado *Interno* / *Visible al ciudadano*.
5. **Gestión como operador** (`operador.prueba@example.com`):
   - En un reporte sin asignar → **Tomar este reporte** → queda "Asignado a Operador Prueba".
   - Cambiar estado → **En atención** (con nota interna opcional) → luego **Cerrado**: exige un mensaje para el ciudadano.
   - Un operador **no** puede gestionar reportes asignados a otra persona ni reabrir cerrados.
   - Si el reporte vino de la app, abra el seguimiento en el teléfono: verá los estados y el mensaje, **nunca** la nota interna ni el nombre del funcionario.
6. **Gestión como supervisor**: asigna o reasigna a cualquier funcionario y puede reabrir un reporte cerrado.
7. **Mapa territorial**: puntos por estado, calor de reportes y, en "Referencia histórica oficial", el calor de los 127.754 delitos 2010–2021 por años y tipo de delito (siempre etiquetado con su fuente).
8. **Estadísticas** (supervisor/administrador): reportes por día, categoría, estado, prioridad, hora y día de la semana; medianas de primera gestión y de cierre; histórico oficial por año, delito, comuna y barrio. El operador ve "Sección restringida".
9. **Administración** (solo administrador):
   - **Personal**: crear cuentas (si no escribe contraseña, se genera una temporal que se muestra una sola vez), cambiar rol, activar o desactivar. No puede quitarse su propio rol.
   - **Categorías**: crear y activar/desactivar; los cambios aparecen de inmediato en la app.
   - **Ajustes**: límite de reportes por ciudadano o dispositivo.
   - **Auditoría**: cada vista de detalle, cambio, asignación, exportación y acción administrativa.
10. **Estado de la plataforma**: verificación de conexiones (API, autenticación, Supabase, almacenamiento, MongoDB).
11. Ingrese como **ciudadano** de Supabase: debe ver "Sin acceso al panel institucional". (Los ciudadanos de la app viven en MongoDB, no en Supabase.)

## 4. Probar la app móvil

> En el emulador también está instalada otra app suya (MonyMonty). Abra la del **escudo azul "AlertaBGA"**.

### Opción A — Emulador (recomendada)
```powershell
flutter emulators --launch Pixel_7
cd mobile
flutter run          # r = hot reload, q = salir
```
No requiere archivos ni comandos extra: en modo debug la app usa la API local vista desde el emulador
(`http://10.0.2.2:8000/api/py`) y la API firma las subidas de fotos para ese mismo host. La app no lleva claves de ninguna base de datos.

### Opción B — Teléfono físico por USB
1. Active "Depuración USB" en el teléfono y conéctelo (`adb devices` debe listarlo).
2. ```powershell
   adb reverse tcp:8000 tcp:8000
   adb reverse tcp:54321 tcp:54321
   cd mobile; flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/py
   ```

### Recorrido de prueba
1. **Bienvenida**: Ingresar · Crear cuenta · Reportar sin cuenta · Consultar radicado, y el aviso del 123.
2. **Reportar sin cuenta**: tipo → ubicación (permita el GPS o **niéguelo** y toque el mapa) → descripción (mín. 10 caracteres) → fotos (opcional, máx. 3) → revisar → **Enviar**.
   Verá el radicado `BGA-AAAA-NNNNNN` y un **código de seguimiento**; quedan guardados en el teléfono (Consultar radicado → "Guardados en este teléfono").
3. **Crear cuenta** (nombre, correo, contraseña de 8+ caracteres, aceptar datos) → entra al inicio con pestañas Inicio · Mis reportes · Perfil.
4. **Reportar un incidente** con la cuenta → aparece en **Mis reportes**; al abrirlo verá la línea de estados (se actualiza cada 30 s).
5. **Recuperar contraseña**: Ingresar → ¿Olvidó su contraseña? → correo → el código de 6 dígitos sale en `docker compose logs api` → código + contraseña nueva.
6. **Configuración** (engranaje): privacidad, borrar reportes anónimos guardados, estado de conexión, emergencias, cerrar sesión.

Pruebe también: marcar un punto fuera de Bucaramanga bloquea el envío; dos toques rápidos en "Enviar" crean **un solo** reporte.

### Ver los datos en MongoDB
```powershell
docker exec -it alertabga_mongo mongosh alertabga --eval "db.incidents.find({}, {radicado:1, status:1, source:1}).sort({received_at:-1}).limit(5)"
docker exec -it alertabga_mongo mongosh alertabga --eval "db.citizens.find({}, {email:1, full_name:1})"
```

### Instalar un APK sin `flutter run`
```powershell
cd mobile
flutter build apk --debug
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
| `EADDRINUSE ... :4000` al hacer `npm run dev` | Ya hay un panel corriendo (p. ej. el que abrió `iniciar-entorno.ps1` en una ventana minimizada): use ese en http://localhost:4000, o ciérrelo con `Get-NetTCPConnection -LocalPort 4000 -State Listen \| % { Stop-Process -Id $_.OwningProcess -Force }` |
| El panel tarda en abrir la primera vez | Es la compilación del modo desarrollo; espere o use `npm run preview` |
| Mongo no arranca en 27017 | Ya hay un MongoDB local en ese puerto; el proyecto usa 27018 |
| Build Android falla con "incremental caches" | Ya está resuelto con `kotlin.incremental=false`. Si persiste: `flutter clean` |
| Tarjeta Supabase en "Con fallas" | Revise que Supabase esté arriba (`npx supabase@2 status`) |
| La app dice "No hay conexión con el servidor" | `docker compose ps` (api debe estar *healthy*); en teléfono físico, repita los `adb reverse` |
| Las fotos no suben ("no se pudieron enviar") | Supabase está apagado, o la API es antigua: `docker compose up -d --build api` |
| Cambié código de la API | `docker compose up -d --build api` |
| Quiero empezar de cero la base local | `npx supabase@2 db reset` (borra usuarios y datos locales) |
| Detener todo | Cierre la ventana de Next; `docker compose down`; `npx supabase@2 stop` |
