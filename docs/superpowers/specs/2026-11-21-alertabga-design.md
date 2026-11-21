# AlertaBGA — Diseño (v1)

Fecha: 2026-11-21 · Estado: aprobado (2026-11-21)
Fuentes: `Documento_Tecnico_AlertaBGA_Seguridad_Ciudadana.docx` (v1.0) y el "Prompt Maestro" del usuario.

## 1. Intención y por qué

Plataforma de seguridad ciudadana para Bucaramanga con dos productos sobre una misma infraestructura:
- **App Android (Flutter)** para que los ciudadanos reporten incidentes geolocalizados, con foto opcional, radicado y seguimiento.
- **Dashboard web (Next.js)** para operadores, supervisores y administradores: recepción, asignación, trazabilidad, retroalimentación al ciudadano y analítica territorial.

El objetivo es un **piloto institucional real y funcional** (persistencia, auth, tiempo real, evidencias privadas), no un prototipo visual. El principio central es que un reporte ciudadano no es un delito confirmado (RB-01) y que el histórico 2010–2021 nunca se presenta como actual.

## 2. Objetivos, no objetivos y anti-objetivos

**Objetivos:** los 20 criterios de aceptación del prompt (cuenta, reporte anónimo, GPS, foto privada en R2, radicado, dashboard en tiempo real, mapa y calor con datos reales, RBAC con RLS, trazabilidad, retroalimentación, histórico separado, producción estable).

**No objetivos (fases posteriores):** predicción de delitos, reconocimiento facial, identificación de sospechosos, despacho automático de patrullas, integración con CAD o cámaras, chat ciudadano-patrulla, iOS, otros municipios.

**Anti-objetivos (fracaso aunque "funcione"):**
- Etiquetar un barrio como "peligroso".
- Mezclar histórico y actual sin etiquetas.
- Fotos o ubicaciones exactas accesibles sin autorización, o claves de R2 en cliente.
- Datos simulados presentados como reales.
- Polígonos de cuadrantes inventados.

## 3. Restricciones

Stack fijo: Next.js, TypeScript, Tailwind, Leaflet o MapLibre en Vercel; FastAPI como funciones serverless Python en el mismo despliegue de Vercel; Flutter y Riverpod en Android; Supabase (Postgres, PostGIS, Auth, Realtime, RLS); Cloudflare R2 para evidencias. Vercel es serverless, así que **no hay WebSockets ni procesos persistentes**. Ley 1581 de 2012. Documentar cuotas y costos de cada proveedor antes de producción.

## 4. Enfoques considerados (base de datos)

1. **Todo en Supabase/Postgres — ELEGIDO por el usuario.** El histórico 2010–2021 va en tablas Postgres separadas (`historical_crimes` y agregados). Una sola base, con RLS, Realtime, Auth y PostGIS nativos.
2. Supabase operativo + MongoDB Atlas solo para el histórico. Descartado: un segundo proveedor sin beneficio claro.
3. Todo en MongoDB. Descartado: contradice el prompt y obliga a rehacer RLS, Auth y tiempo real.

**Nota de decisión:** esto reemplaza la mención a MongoDB del Word y de la nota final del usuario. Se registrará como ADR. PySpark queda fuera del MVP: Postgres y SQL agregan 135 mil filas sin problema. Si se necesita, se usa como ETL de una sola vez.

## 5. Arquitectura

```
Flutter (Android) ─┐                        ┌─► Supabase Realtime ─► Dashboard
                   ├─HTTPS─► Vercel ────────┤        (eventos reales de BD)
Next.js (web) ─────┘   Next.js + /api/py/*  │
                       (FastAPI serverless)  ├─► Supabase Postgres/PostGIS + Auth + RLS
                              │              └─► Cloudflare R2 (privado)
                              └─ URLs firmadas de corta duración (PUT/GET)
```

- **Python en Vercel:** FastAPI como una función ASGI en `web/api/index.py`. `vercel.json` reescribe `/api/py/*` hacia ella. Dependencias en `requirements.txt`. Sin estado entre invocaciones, con conexión a Supabase por pooler (transaction mode).
- **Autenticación:** Supabase Auth emite el JWT. FastAPI lo valida (JWKS) y consulta con el rol del usuario. RLS es la barrera final; FastAPI aplica RBAC antes y registra auditoría.
- **Anónimos:** no usan cuenta. `POST /reports/anonymous` crea el incidente con `reporter_id` nulo. Devuelve un radicado y un token de seguimiento aleatorio (≥128 bits); en BD solo se guarda su hash. Se consulta con radicado + token. Hay límite de frecuencia por IP/dispositivo, sin guardar identidad.
- **Evidencias:** el cliente pide `POST /evidence/presign` (valida MIME, tamaño y propiedad del incidente), sube directo a R2 con URL PUT firmada y confirma con `POST /evidence/confirm`. La lectura usa una URL GET firmada de pocos minutos, y cada acceso se escribe en `audit_logs`. Las claves de R2 solo existen en variables de entorno de Vercel.
- **Tiempo real:** el dashboard se suscribe con Supabase Realtime (Postgres Changes) a `incidents`, `assignments` e `institutional_messages`, filtradas por RLS. La app móvil se suscribe a su propio incidente. No hay simulación.
- **Cuadrante:** función SQL `ST_Contains` sobre `quadrants.boundary`. Si no hay polígonos cargados, `quadrant_id` queda nulo y el incidente entra en la cola de asignación manual. Mientras no haya datos oficiales, no se inventan límites.

## 6. Modelo de datos (11 tablas mínimas)

`profiles` (1:1 con auth.users, `role_id`, cuadrantes de ámbito), `roles` (ciudadano, operador, supervisor, administrador), `categories` (nombre, descripción, icono, color, severidad, activa), `incidents` (radicado único, `geography(Point,4326)` con índice GiST, `accuracy_m`, `occurred_at`, `received_at` por defecto `now()` del servidor, estado, prioridad sugerida, fuente, `reporter_id` nullable, `quadrant_id`, `verification_level`: reporte/verificado/confirmado, hash del token anónimo), `quadrants`, `evidence`, `assignments`, `incident_history` (solo inserción: triggers que bloquean UPDATE y DELETE), `institutional_messages` (visibles al ciudadano; las notas internas viven en `incident_history`), `notifications`, `audit_logs` (solo inserción).

Tablas adicionales (mi llamada): `historical_crimes` y `historical_aggregates` (2010–2021, con `source` y `period` explícitos) y `app_settings` (ámbito territorial, límites).

Radicado: formato `BGA-AAAA-NNNNNN` generado por función SQL con secuencia.

RLS por rol:
- El ciudadano ve solo lo suyo y solo mensajes institucionales.
- El operador ve su cuadrante.
- El supervisor ve su ámbito.
- El administrador ve todo.

Los estados son `RECIBIDO`, `EN_REVISION`, `ASIGNADO`, `EN_ATENCION`, `CERRADO` y `NO_PROCEDE`. Las transiciones se validan en una función SQL y cada cambio escribe en el historial.

## 7. Estructura del repo


```
AlertaBGA/
  web/        Next.js (app/, components/, modules/, hooks/, services/, lib/, types/, styles/) + api/ (FastAPI)
  mobile/     Flutter (lib/core, config, models, services, repositories, features, widgets)
  database/   migrations/, policies/, seeds/, functions/
  docs/       specs, ADRs, variables de entorno, cuotas y costos, despliegue
```

## 8. Datos externos (Fase 0, investigación)

- **Histórico:** descargar el dataset "Delitos ocurridos en el Municipio de Bucaramanga" (probablemente datos.gov.co). Validar 135.076 filas y 19 variables, y limpiar coordenadas (125.108 válidas) antes de cargar a `historical_crimes`.
- **Datos recientes:** buscar fuentes oficiales posteriores a 2021. Si no hay una fuente verificable, la línea base queda en 2021 y así se etiqueta. No se usa como "mes actual".
- **Cuadrantes:** buscar en fuentes oficiales los cuadrantes de Bucaramanga, su personal y su cobertura. Sin polígonos oficiales, la asignación es manual y se deja lista la carga de GeoJSON.

## 9. Fases (según el prompt, con puerta de salida)

0. Preparación: repo, ADRs, proyectos Supabase/Vercel/R2/Flutter, esquema inicial y verificación de conexiones entre componentes.
1. Infraestructura y auth: migraciones, roles, RLS, FastAPI en Vercel, "hola mundo" end-to-end entre móvil, web, Python, Supabase y R2.
2. App ciudadana.
3. Dashboard (panel, mapa, calor, bandeja, detalle).
4. Gestión institucional (asignación, estados, trazabilidad, retroalimentación).
5. Analítica (estadísticas, sectores, comparación, histórico, exportación).
6. Pruebas (unitarias, integración, permisos RLS, geoespaciales, Android) y producción.

Cada fase termina con comandos exactos para ejecutarla y comprobarla. No se pasa a la siguiente si la anterior falla.

## 10. Decisiones mías (a revisar)

- Se omite PySpark del MVP (§4).
- Se excluye cualquier "Firebase como BD". FCM (push) queda para una fase tardía y opcional.
- El tamaño de imagen será ≤ 5 MB y los MIME serán `image/jpeg`, `image/png` y `image/webp`; hasta 3 fotos por reporte. Son parámetros ajustables.
- Mapas: MapLibre/Leaflet con teselas de OpenStreetMap solo para desarrollo. Hay que revisar los términos de uso antes de producción y elegir un proveedor.
- Límite de frecuencia: p. ej. 5 reportes por hora por dispositivo o IP. Es un parámetro y se ajusta con la entidad.
- Ámbito territorial: un polígono de Bucaramanga cargado en `app_settings`, hasta tener límites oficiales.
- Si el prompt y el Word chocan, manda el prompt, salvo en las notas del usuario sobre datos y cuadrantes.

## 11. Preguntas resueltas (el usuario delegó todas las decisiones)

1. Cuentas cloud: todo se desarrolla y prueba contra **Supabase local (CLI + Docker)**. Las cuentas de Supabase, Vercel y Cloudflare R2 las crea el usuario cuando quiera desplegar; los pasos quedan en `docs/configuracion/`.
2. Entorno: Flutter 3.47.8, Android SDK/adb, Node 23, Python 3.11 y Docker están instalados en la máquina de desarrollo.
3. Nombre: AlertaBGA se usa como nombre del piloto; la validación de marca queda como tarea institucional fuera del código.
