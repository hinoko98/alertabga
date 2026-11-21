# ADR 0001 — Persistencia: Supabase (operativo) + MongoDB (histórico y analítica) + PySpark (procesamiento por lotes)

- Estado: aceptado · Fecha: 2026-11-21 · Revisión 2 (reemplaza "Supabase como base única")

## Contexto
- El prompt maestro exige Supabase (PostgreSQL + PostGIS + Auth + Realtime + RLS) para toda la información operacional.
- El documento técnico v1.0 y la entrega académica (Fase 2 → Fase 3) plantean MongoDB como base NoSQL y PySpark/Spark SQL como motor analítico por lotes.
- El usuario indicó explícitamente conservar MongoDB y PySpark, con el histórico "migrado a Mongo e integrado dentro del backend".

## Decisión
| Componente | Responsabilidad | Por qué allí |
|---|---|---|
| **Supabase/Postgres** | Operación: perfiles, roles, incidentes, evidencias, asignaciones, historial, mensajes, auditoría | RLS, Auth y Realtime son nativos y obligatorios por el prompt |
| **MongoDB** (Atlas en producción, `mongo:7` en Docker local) | Histórico 2010–2021 (`historical_crimes`), capas agregadas (`historical_aggregates`) y, en el futuro, datos institucionales externos | Continuidad con la entrega académica; esquema flexible para fuentes heterogéneas; índice `2dsphere` |
| **PySpark** (carpeta `analytics/`) | ETL: limpieza, validación de coordenadas, exclusión de otros municipios, agregaciones por año, mes, barrio, comuna y categoría; escribe en MongoDB | Se reutiliza el pipeline de la Fase 2. Se ejecuta en local, Colab o un runner programado, **nunca en Vercel** |

- FastAPI (en Vercel) lee MongoDB con `pymongo`, reutilizando la conexión por instancia, y expone `/api/py/historico/*`.
- El histórico siempre sale con `periodo: "2010-2021"` y `fuente`.
- Los reportes operativos nunca se escriben en Mongo como fuente de verdad. Si Spark los procesa en el futuro, los lee como exportación de solo lectura de Supabase y los etiqueta aparte.

## Alternativas descartadas
- Todo en Supabase: no respeta la decisión del usuario de conservar Mongo y PySpark.
- Todo en Mongo: obliga a rehacer RLS, Auth y Realtime, y contradice el prompt.

## Consecuencias
- Hay dos proveedores de datos, con dos cuotas, dos backups y dos conjuntos de credenciales (`MONGODB_URI`).
- Para las cuotas de Atlas, ver `docs/configuracion/cuotas-y-costos.md`.
- Las conexiones Mongo desde funciones serverless requieren permitir el acceso de red desde Vercel (IP dinámica) en Atlas.
- PySpark requiere Java 17+ en la máquina que ejecute el ETL.
