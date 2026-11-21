# ADR 0001 — Supabase/PostgreSQL como única base de datos

- Estado: aceptado · Fecha: 2026-11-21

## Contexto
El documento técnico v1.0 proponía MongoDB como base operacional y WebSocket/SSE para el tiempo real. El prompt maestro exige Supabase (PostgreSQL + PostGIS + Auth + Realtime + RLS) y despliegue serverless en Vercel. Una nota del usuario mencionaba migrar el histórico a Mongo.

## Alternativas
1. **Todo en Supabase/Postgres.** El histórico va en tablas separadas y etiquetadas.
2. Supabase para lo operativo + MongoDB Atlas para el histórico.
3. Todo en MongoDB.

## Decisión
Alternativa 1, elegida por el usuario.

## Consecuencias
- RLS, Realtime, Auth y PostGIS son nativos: no hay que reconstruir seguridad ni tiempo real.
- Es un solo proveedor de datos, con una sola cuota y un solo backup.
- Los 135.076 registros históricos se agregan con SQL; PySpark no es necesario en el MVP.
- La analítica histórica comparte base con la operación. Si el volumen crece mucho, se separa en un esquema o réplica de lectura.
