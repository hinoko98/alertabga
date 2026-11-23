# Variables de entorno

Ningún secreto se versiona. Las plantillas son `web/.env.example` y `mobile/env.example.json`.

## Web + API (`web/.env.local` en desarrollo · Vercel → Settings → Environment Variables en producción)

| Variable | Expuesta al navegador | Uso |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | sí | URL del proyecto Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | sí | Clave pública (anon/publishable). RLS protege los datos |
| `SUPABASE_URL` | no | La misma URL, leída por FastAPI |
| `SUPABASE_ANON_KEY` | no | FastAPI la usa con el JWT del usuario, así RLS aplica |
| `SUPABASE_SERVICE_ROLE_KEY` | **no — secreto** | Solo FastAPI: creación anónima, auditoría, rate limit |
| `SUPABASE_JWT_SECRET` | **no — secreto** | Opcional. Si existe, valida JWT HS256 (Supabase local/legado). Si no, se usa JWKS |
| `R2_ACCOUNT_ID` | no | Cuenta Cloudflare |
| `R2_ACCESS_KEY_ID` | **no — secreto** | Token S3 de R2 restringido al bucket |
| `R2_SECRET_ACCESS_KEY` | **no — secreto** | Token S3 de R2 |
| `R2_BUCKET` | no | p. ej. `alertabga-evidencias` (privado) |
| `R2_ENDPOINT_URL` | no | Solo local: `http://127.0.0.1:54321/storage/v1/s3` (Supabase Storage S3 sustituye a R2). Vacío en producción |
| `R2_PUBLIC_ENDPOINT_URL` | no | Solo local: host con el que se firman las URL de subida. Admite `{host}` = host por el que el cliente llamó a la API (Docker usa `http://{host}:54321/storage/v1/s3`: emulador → 10.0.2.2, navegador → localhost). Vacío en producción |
| `R2_REGION` | no | `auto` en R2; `local` en Supabase local |
| `RATE_LIMIT_SALT` | **no — secreto** | Sal aleatoria larga para las claves anónimas de rate limit y el hash de IP |
| `CITIZEN_JWT_SECRET` | **no — secreto** | Firma las sesiones de la app ciudadana (32+ caracteres). Ver ADR 0003 |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM` | `SMTP_PASSWORD` es secreto | Correo del código de recuperación. Sin `SMTP_HOST` el código se escribe en el log de la API (solo local) |
| `API_ALLOWED_ORIGINS` | no | CORS, separado por comas |

## Móvil (opcional, `--dart-define`)

| Clave | Uso |
|---|---|
| `API_BASE_URL` | Base de FastAPI. En debug, si no se pasa, usa `http://10.0.2.2:8000/api/py` (API local desde el emulador): basta `flutter run`. Obligatoria en release: `--dart-define=API_BASE_URL=https://<dominio>/api/py` |

La app móvil **nunca** recibe claves de Supabase, de R2 ni de bases de datos: solo la URL de la API (ADR 0003).

## Supabase local
`npx supabase start` imprime la URL, la anon key, la service role key y el JWT secret locales. Esos valores son de desarrollo y no sirven en producción.
