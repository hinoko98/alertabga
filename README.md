# AlertaBGA

Plataforma de seguridad ciudadana para Bucaramanga: app Android de reportes geolocalizados y dashboard institucional de gestión y analítica.

> La app no reemplaza las líneas oficiales de emergencia (123). Un reporte ciudadano no es un delito confirmado.

## Estructura

| Carpeta | Contenido |
|---|---|
| `supabase/` | Migraciones SQL, políticas RLS, semillas y pruebas pgTAP (Supabase CLI) |
| `web/` | Dashboard Next.js + API FastAPI (`web/api`) — un solo proyecto Vercel |
| `mobile/` | App Flutter (Android) |
| `docs/` | Diseño, planes, ADR, configuración, fuentes de datos |

## Desarrollo local

Requisitos: Node ≥ 20, Python 3.11, Docker Desktop, Flutter ≥ 3.38, Android SDK.

```bash
# 1. Base de datos local (Docker debe estar corriendo)
npx supabase start          # imprime URL y claves locales
npx supabase db reset       # aplica migraciones + semilla
npx supabase test db        # pruebas pgTAP (esquema, negocio, RLS)

# 2. API
cd web
python -m venv .venv && .venv/Scripts/activate   # Windows
pip install -r requirements.txt -r requirements-dev.txt
pytest
uvicorn api.index:app --reload --port 8000

# 3. Dashboard (otra terminal)
cd web
cp .env.example .env.local  # completar con los valores de `supabase start`
npm install
npm run dev                 # http://localhost:3000

# 4. App móvil
cd mobile
cp env.example.json env.json
flutter pub get
flutter run --dart-define-from-file=env.json
```

Ver `docs/configuracion/` para variables de entorno, despliegue, cuotas y costos.
