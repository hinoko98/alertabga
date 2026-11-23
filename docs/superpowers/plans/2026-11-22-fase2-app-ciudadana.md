# AlertaBGA — Fase 2: App ciudadana

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** un ciudadano registra cuenta o reporta de forma anónima desde Android, con GPS, mapa, fotos (cámara o galería) almacenadas de forma privada, radicado único y seguimiento con la retroalimentación institucional.

**Architecture:** la creación de reportes, el seguimiento anónimo y las evidencias pasan por FastAPI, que aplica validación, rate limit, token anónimo y URLs firmadas. La autenticación, el perfil y las lecturas propias usan Supabase con RLS. Las fotos van directo del teléfono al almacenamiento S3 (R2 en producción; en local, la interfaz S3 de Supabase Storage) mediante una URL PUT firmada; la API confirma con HEAD.

**Tech Stack:** FastAPI, supabase-py, boto3 · Supabase Storage S3 (sustituto local de R2, sin contenedor extra) · Flutter, Riverpod 3, go_router, geolocator, flutter_map + latlong2 (OSM), image_picker, flutter_secure_storage, shared_preferences, url_launcher, intl.

**Spec:** `docs/superpowers/specs/2026-11-21-alertabga-design.md` (§5 anónimos, evidencias, tiempo real; §6 modelo).

## Global Constraints
- Evidencias: `image/jpeg|image/png|image/webp`, ≤ 5 242 880 bytes, ≤ 3 por incidente; clave `incidents/{incident_id}/{evidence_id}.{ext}`; URL PUT/GET de 300 s.
- Token anónimo: `secrets.token_urlsafe(32)` (256 bits). En BD solo `sha256(token)` hex. Comparación con `hmac.compare_digest`. Radicado inexistente y token erróneo responden **igual** (404 "Radicado o código no válido").
- Rate limit de reportes: `app_settings.rate_limit_reports` (5 por 60 min). Clave anónima: `sha256(RATE_LIMIT_SALT + ip + X-Device-Id)`; autenticada: `user:{id}`. Exceso → 429. Seguimiento anónimo: 20 por 10 min por IP.
- `occurred_at` no puede ser futuro (> now + 5 min). Descripción de 10 a 2000 caracteres. Lat −90..90, lon −180..180, `accuracy_m` ≥ 0.
- El ciudadano nunca ve notas internas: el timeline público son las filas de `incident_history` con `is_internal = false` más `institutional_messages`.
- La app bloquea el envío fuera del ámbito (bbox de `app_settings.territorial_scope`). El servidor igualmente marca `out_of_scope`.
- Advertencia visible antes de las fotos: no perseguir ni confrontar a sospechosos. Advertencia permanente: la app no reemplaza el 123.
- UI en español, botones grandes, el estado nunca depende solo del color.

## Review Focus
1. Enumerar radicados ajenos vía `/reports/track` o `/reports/{radicado}` → siempre 404 uniforme. Pruebas en Task 2.
2. Subir evidencia a un incidente ajeno (autenticado no dueño, o anónimo sin token válido) → 404. Prueba en Task 3.
3. El timeline anónimo filtra una nota interna → nunca aparece. Pruebas en Task 2 y en E2E.
4. GPS denegado o apagado → la app permite elegir en el mapa (`location_manual = true`). Task 6.
5. Reenviar el formulario dos veces por doble toque → el botón queda deshabilitado mientras envía. Task 6.

---

### Task 1: Almacenamiento S3 local y storage configurable
> Decisión: en vez de MinIO se usa la interfaz S3 que ya trae Supabase local (bucket privado creado en `supabase/seed.sql`). Menos piezas y mismo protocolo que R2.

**Files:** `supabase/seed.sql` (bucket local), `web/api/_lib/alertabga/config.py` (`r2_endpoint_url`, `r2_public_endpoint_url`, `rate_limit_salt`), `web/api/_lib/alertabga/storage.py`, `web/tests/api/test_storage.py`
**Produces:** `presign_put(key, mime, size) -> str` firmado con el endpoint público; `head(key) -> {size, mime} | None`; `delete(key)`.
- [x] Pruebas: mime inválido → ValueError; tamaño 0 o > 5 MB → ValueError; la URL firmada usa el host de `r2_public_endpoint_url`.

### Task 2: API de reportes y seguimiento
**Files:** `web/api/_lib/alertabga/reports/{__init__,schemas,repository,service}.py`, `web/api/_lib/alertabga/routers/reports.py`, `web/tests/api/test_reports.py`
**Produces:**
- `POST /api/py/reports` (Bearer, rol ciudadano) → 201 `{id, radicado, received_at, status, out_of_scope}`
- `POST /api/py/reports/anonymous` (sin auth, header `X-Device-Id`) → 201 `{..., tracking_token}`
- `GET /api/py/reports/mine` (Bearer) → lista `{radicado, category, status, received_at}`
- `GET /api/py/reports/{radicado}` (Bearer, dueño) → detalle + `timeline[]`
- `POST /api/py/reports/track` `{radicado, token}` → detalle público + `timeline[]`
- `GET /api/py/categories` → categorías activas
- `ReportRepository` (Protocol) + `SupabaseReportRepository`; `ReportService(repo)` con la lógica.
- [x] Pruebas con `FakeRepository`: el anónimo devuelve token y guarda solo el hash; 429 al sexto reporte; categoría inactiva → 422; futuro → 422; track con token erróneo y con radicado inexistente → mismo 404; el timeline excluye internos; el autenticado no ve el radicado de otro → 404.

### Task 3: API de evidencias
**Files:** `web/api/_lib/alertabga/routers/evidence.py`, `web/api/_lib/alertabga/reports/evidence_service.py`, `web/tests/api/test_evidence.py`
**Produces:** `POST /api/py/evidence/presign` `{radicado, mime, size, tracking_token?}` → `{evidence_id, upload_url, headers}`; `POST /api/py/evidence/{id}/confirm` `{radicado, tracking_token?}` → `{status}`. Auditoría `EVIDENCIA_SUBIDA`.
- [x] Pruebas: el cuarto archivo → 409; mime o tamaño inválido → 422; no dueño o token inválido → 404; confirm con HEAD distinto → `RECHAZADA` y borrado del objeto; confirm correcto → `CONFIRMADA`.

### Task 4: E2E backend real
**Files:** `web/scripts/verificar-reportes.mjs`
- [x] Contra el stack local: reporte anónimo → track → presign → PUT al S3 local → confirm; ciudadano autenticado → reporte → `/mine`; admin recibe el INSERT por Realtime; el track nunca devuelve `NOTA_INTERNA` (se inserta una antes de consultar).

### Task 5: App — base, sesión y navegación
**Files:** `mobile/lib/core/{storage/secure_store.dart, device/device_id.dart, network/api_client.dart, network/api_error.dart}`, `mobile/lib/core/router/app_router.dart`, `mobile/lib/features/auth/{data/auth_repository.dart, presentation/{splash_screen,welcome_screen,login_screen,register_screen,forgot_password_screen,reset_password_screen}.dart}`, `mobile/lib/features/home/home_shell.dart`, AndroidManifest (deep link `co.gov.alertabga://login-callback`, permisos de ubicación y cámara), `supabase/config.toml` (redirect URL)
- [ ] Pruebas widget: la bienvenida muestra Ingresar / Crear cuenta / Reportar sin cuenta / Consultar radicado; el registro valida correo y contraseña ≥ 8.

### Task 6: App — flujo de reporte
**Files:** `mobile/lib/features/report/{domain/report_draft.dart, data/report_repository.dart, application/report_controller.dart, presentation/{report_flow_screen,category_step,location_step,details_step,photos_step,review_step,confirmation_screen}.dart}`, `mobile/lib/core/geo/territorial_scope.dart`
- [ ] Pruebas unitarias: `ReportDraft.validate()` (categoría, descripción de 10 a 2000, ubicación, máx. 3 fotos); `TerritorialScope.contains`; el controlador deshabilita el envío mientras `submitting`.

### Task 7: App — mis reportes, seguimiento, perfil, configuración, emergencias
**Files:** `mobile/lib/features/tracking/{data/tracking_repository.dart, presentation/{my_reports_screen,tracking_screen,track_lookup_screen}.dart, widgets/status_timeline.dart}`, `mobile/lib/features/profile/profile_screen.dart`, `mobile/lib/features/settings/settings_screen.dart`, `mobile/lib/features/emergency/emergency_screen.dart`, `mobile/lib/core/domain/incident_status.dart`
- Seguimiento autenticado: Realtime sobre `incidents` (`id=eq`) e `institutional_messages`. Anónimo: deslizar para refrescar.
- Reportes anónimos guardados en el dispositivo (secure storage) con radicado y token.
- [ ] Pruebas: `IncidentStatus` mapea los 6 estados a etiqueta, icono y paso; `StatusTimeline` muestra mensajes institucionales.

### Task 8: Verificación integral y guía
- [ ] `scripts/verificar-todo.ps1` en verde; APK debug instalado en el emulador; reporte real desde la app visible en el panel. Actualizar `docs/GUIA-PRUEBAS.md`.
