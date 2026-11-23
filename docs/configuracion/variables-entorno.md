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
| `R2_PUBLIC_ENDPOINT_URL` | no | Solo local: host que verá el teléfono en la URL firmada (emulador: `http://10.0.2.2:54321/storage/v1/s3`) |
| `R2_REGION` | no | `auto` en R2; `local` en Supabase local |
| `RATE_LIMIT_SALT` | **no — secreto** | Sal aleatoria larga para las claves anónimas de rate limit y el hash de IP |
| `API_ALLOWED_ORIGINS` | no | CORS, separado por comas |

## Móvil (`mobile/env.json`, pasado con `--dart-define-from-file=env.json`)

| Clave | Uso |
|---|---|
| `SUPABASE_URL` | URL Supabase (desde el emulador Android, la local es `http://10.0.2.2:54321`) |
| `SUPABASE_ANON_KEY` | Clave pública |
| `API_BASE_URL` | Base de FastAPI, p. ej. `https://<proyecto>.vercel.app/api/py` o `http://10.0.2.2:8000/api/py` |

La app móvil **nunca** recibe la service role ni las claves de R2.

## Supabase local
`npx supabase start` imprime la URL, la anon key, la service role key y el JWT secret locales. Esos valores son de desarrollo y no sirven en producción.
