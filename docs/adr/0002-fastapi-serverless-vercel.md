# ADR 0002 — FastAPI como función serverless dentro del proyecto Next.js en Vercel

- Estado: aceptado · Fecha: 2026-11-21

## Contexto
El backend debe ser Python/FastAPI sin contratar un servidor independiente. Vercel ejecuta funciones serverless, no procesos permanentes.

## Decisión
- El proyecto Vercel es `web/`. Vercel trata cualquier archivo `web/api/*.py` como función Python.
- `web/api/index.py` expone una app ASGI de FastAPI con prefijo `/api/py`. `vercel.json` reescribe `/api/py/(.*)` hacia `/api/index`.
- En desarrollo local, `next.config.ts` reescribe `/api/py/:path*` hacia `http://127.0.0.1:8000` (uvicorn).
- Dependencias Python en `web/requirements.txt`.
- Las funciones no guardan estado. Supabase se accede por HTTP (PostgREST, con supabase-py), sin pools persistentes.
- Los límites de frecuencia viven en Postgres (`check_rate_limit`) y no en memoria.

## Tiempo real
No hay WebSockets propios. Los clientes se suscriben a Supabase Realtime (Postgres Changes). Los eventos salen de inserts y updates reales y se filtran por RLS con el JWT del usuario.

## Consecuencias
- Hay arranques en frío de 1 a 3 s en la primera invocación.
- La duración por invocación está limitada según el plan de Vercel (ver `docs/configuracion/cuotas-y-costos.md`). Ningún endpoint hace trabajo largo; la carga histórica se ejecuta como script local.
- El bundle Python debe quedar por debajo del límite de tamaño de función (250 MB descomprimido).
