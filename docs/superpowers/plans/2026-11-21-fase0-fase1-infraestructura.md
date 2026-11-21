# AlertaBGA — Fase 0 y Fase 1: Infraestructura y autenticación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** monorepo funcional con esquema Supabase (PostGIS, RLS, triggers de trazabilidad), FastAPI serverless dentro del proyecto Next.js para Vercel, y apps web y móvil que se autentican con Supabase y verifican la conexión con el backend.

**Architecture:** Supabase es la única base de datos. FastAPI vive en `web/api/index.py` y Vercel lo expone en `/api/py/*`. Opera con el JWT del usuario para que RLS aplique, y usa la service role solo para la creación anónima y la auditoría. R2 se accede únicamente desde FastAPI mediante URLs firmadas.

**Tech Stack:** Supabase CLI (local con Docker), Postgres 15+, PostGIS, pgTAP · Next.js 16, TypeScript, Tailwind v4, @supabase/ssr · Python 3.11, FastAPI, Pydantic v2, supabase-py, PyJWT, boto3, pytest · Flutter 3.47, Riverpod, supabase_flutter, go_router, dio.

**Spec:** `docs/superpowers/specs/2026-11-21-alertabga-design.md`

## Global Constraints

- Las migraciones viven en `supabase/migrations` (convención del CLI). Esto reemplaza `database/` del prompt, permitido por "adaptarse a las convenciones".
- No hay secretos en el repo. `.env*`, `env.json` y `supabase/.env` van en `.gitignore`. Se documentan en `docs/configuracion/variables-entorno.md`.
- Estados: `RECIBIDO, EN_REVISION, ASIGNADO, EN_ATENCION, CERRADO, NO_PROCEDE`.
- Nivel de verificación: `REPORTE_CIUDADANO, CASO_VERIFICADO, DELITO_CONFIRMADO`.
- Roles: `ciudadano, operador, supervisor, administrador`.
- Radicado: `BGA-AAAA-NNNNNN`. `received_at` siempre lo fija el servidor.
- Evidencias: `image/jpeg|image/png|image/webp`, ≤ 5 242 880 bytes, ≤ 3 por incidente.
- Categorías semilla: **solo** Hurto, Robo de vehículos, Riñas y agresiones. El resto lo carga el administrador; no se inventan.
- Cuadrantes: no se siembran polígonos. Si `boundary` es nulo, `quadrant_id` queda nulo y el incidente va a la cola manual.
- Toda la UI en español (Colombia).

## Review Focus

1. Un operador intenta leer o actualizar un incidente de otro cuadrante → RLS devuelve 0 filas. Prueba pgTAP en la Tarea 4.
2. Un cliente intenta fijar `received_at`, `radicado` o `status` en el insert → el servidor los sobreescribe. Prueba pgTAP en la Tarea 3.
3. UPDATE o DELETE sobre `incident_history` o `audit_logs`, incluso como administrador → error. Prueba pgTAP en la Tarea 3.
4. JWT vencido, mal firmado o ausente en FastAPI → 401 sin filtrar detalles. Prueba pytest en la Tarea 5.
5. Transición de estado inválida (p. ej. `CERRADO → EN_ATENCION`, o `NO_PROCEDE` sin motivo) → error. Prueba pgTAP en la Tarea 3.

---

### Task 1: Repo, ADR y documentación base
**Files:** `.gitignore`, `README.md`, `docs/adr/0001-supabase-base-unica.md`, `docs/adr/0002-fastapi-serverless-vercel.md`, `docs/configuracion/variables-entorno.md`, `docs/configuracion/cuotas-y-costos.md`
- [ ] `git init`, `.gitignore` (node, python, flutter, env), commit inicial con spec y plan.

### Task 2: Supabase local + esquema núcleo
**Files:** `supabase/config.toml` (via `npx supabase init`), `supabase/migrations/20261121000100_extensiones_y_tipos.sql`, `..._000200_tablas_nucleo.sql`, `supabase/seed.sql`, `supabase/tests/001_esquema.sql`
**Produces:** tablas `roles, profiles, profile_quadrants, categories, quadrants, incidents, evidence, assignments, incident_history, institutional_messages, notifications, audit_logs, app_settings, rate_limits`. Enums `incident_status, verification_level, report_source, incident_priority`.
- [ ] Prueba pgTAP: `has_table` para las 11 tablas mínimas, índice GiST en `incidents.location`, 3 categorías semilla, 4 roles.
- [ ] `npx supabase test db` → FAIL. Escribir migraciones y semilla → PASS. Commit.

### Task 3: Funciones y triggers de negocio
**Files:** `supabase/migrations/20261121000300_funciones_negocio.sql`, `supabase/tests/002_negocio.sql`
**Produces:**
- `generate_radicado() returns text`
- `assign_quadrant(geography) returns uuid`
- `check_rate_limit(p_key text, p_max int, p_window interval) returns boolean`
- Trigger `incidents_before_insert`: fuerza radicado, `received_at=now()`, `status='RECIBIDO'`, `verification_level='REPORTE_CIUDADANO'`, cuadrante.
- `incidents_after_insert`: historial `CREADO`, no interno.
- `incidents_before_update`: valida transiciones; `NO_PROCEDE` y `CERRADO` exigen `closure_reason`.
- `incidents_after_update`: historial de cambio de estado, cuadrante y asignado.
- `prevent_mutation()` en `incident_history` y `audit_logs`.
- `create_citizen_profile` en `auth.users`, con rol `ciudadano`.
- [ ] Pruebas: radicado con formato regex `^BGA-\d{4}-\d{6}$`; `received_at` del cliente ignorado; transición inválida lanza; UPDATE o DELETE del historial lanza; rate limit devuelve false en el intento máx+1; alta en auth crea profile ciudadano.
- [ ] FAIL → implementar → PASS → commit.

### Task 4: Políticas RLS
**Files:** `supabase/migrations/20261121000400_rls.sql`, `supabase/tests/003_rls.sql`
**Produces:** helpers `auth_role() returns text`, `can_access_quadrant(uuid) returns boolean` (security definer, stable).
- Ciudadano: ve sus incidentes, los mensajes institucionales y el historial no interno de sus incidentes. Sin INSERT ni UPDATE directos (van por API).
- Operador: SELECT y UPDATE de incidentes de sus cuadrantes.
- Supervisor: sus cuadrantes más la cola sin cuadrante; además lee la auditoría.
- Administrador: todo, incluido el CRUD de categorías, cuadrantes y perfiles.
- `audit_logs`: sin INSERT para `authenticated`; solo `service_role`.
- Realtime: publicación `supabase_realtime` con `incidents, assignments, institutional_messages, incident_history`.
- [ ] Pruebas con `set local role authenticated` + `request.jwt.claims`: operador A ve 1 incidente y no el de B; ciudadano ve solo el suyo; ciudadano no puede insertar en `incidents`; anon no lee nada; supervisor ve la cola sin cuadrante.
- [ ] FAIL → implementar → PASS → commit.

### Task 5: FastAPI serverless
**Files:** `web/api/index.py`, `web/api/alertabga/{__init__,config,auth,deps,supabase_client,storage,audit}.py`, `web/api/alertabga/routers/{health,me}.py`, `web/requirements.txt`, `web/api/tests/{conftest,test_health,test_auth}.py`, `web/pytest.ini`
**Produces:**
- `GET /api/py/health` → `{"status":"ok","service":"alertabga-api","time":ISO}`
- `GET /api/py/health/deps` → estado de Supabase y R2 (configurado o no)
- `GET /api/py/me` → `{"id","role","full_name"}` con Bearer
- `verify_jwt(token) -> Claims`: HS256 con `SUPABASE_JWT_SECRET` si existe; si no, JWKS de `{SUPABASE_URL}/auth/v1/.well-known/jwks.json`
- `presign_put(key, mime, size) / presign_get(key, ttl=300)`
- [ ] Pruebas: health 200; `/me` sin token → 401; firma inválida → 401; vencido → 401; válido → 200 con el rol del perfil (perfil con monkeypatch).
- [ ] FAIL → implementar → PASS → commit.

### Task 6: Dashboard Next.js (esqueleto conectado)
**Files:** `web/` (create-next-app), `web/vercel.json`, `web/next.config.ts` (rewrite de `/api/py` al uvicorn local en dev), `web/lib/supabase/{client,server}.ts`, `web/middleware.ts` → `web/proxy.ts` según Next 16, `web/app/(auth)/login/page.tsx`, `web/app/(panel)/layout.tsx`, `web/app/(panel)/page.tsx` (estado del sistema), `web/styles` con tokens de marca
- Solo roles institucionales entran al panel; un ciudadano que inicie sesión ve "sin acceso".
- [ ] `npm run build` y `npm run lint` pasan. Commit.

### Task 7: App Flutter (esqueleto conectado)
**Files:** `mobile/` (`flutter create --platforms android --org co.gov.alertabga`), `mobile/lib/core/config/env.dart`, `mobile/lib/core/theme/app_theme.dart`, `mobile/lib/core/network/api_client.dart`, `mobile/lib/app.dart`, `mobile/lib/main.dart`, `mobile/lib/features/system/system_status_screen.dart`, `mobile/test/env_test.dart`
- Configuración vía `--dart-define-from-file=env.json`.
- [ ] `flutter analyze` sin errores y `flutter test` pasa. Commit.

### Task 8: Investigación de fuentes de datos
**Files:** `docs/datos/fuentes.md`
- [ ] Localizar el dataset histórico (URL oficial, licencia, columnas), fuentes posteriores a 2021 y fuentes oficiales de cuadrantes (MNVCC, Policía Metropolitana de Bucaramanga). Registrar qué se encontró y qué no, sin inventar. Commit.
