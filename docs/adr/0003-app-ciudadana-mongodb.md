# ADR 0003 — La app ciudadana usa solo la API, y sus datos viven en MongoDB

- Estado: aceptado · Fecha: 2026-11-22 · Modifica el ADR 0001 (la fila "Supabase/Postgres" ya no incluye incidentes ni ciudadanos)

## Contexto
El usuario pidió que la app móvil no use Supabase y que trabaje con MongoDB. Para el panel web aceptó cualquiera de las dos bases.
Un teléfono no puede conectarse directo a MongoDB sin exponer credenciales, así que toda la app pasa por FastAPI.

## Decisión
| Dato | Dónde | Quién lo toca |
|---|---|---|
| Cuentas ciudadanas (correo, hash scrypt, nombre, teléfono) | MongoDB `citizens` | API (`/api/py/auth/*`, `/api/py/account`) |
| Sesiones ciudadanas | JWT HS256 de la API (15 min) + refresh token opaco rotativo, guardado como sha256 en `citizen_sessions` (TTL) | API |
| Reportes, historial público e interno, mensajes, evidencias | MongoDB `incidents`, `incident_history`, `evidence` | API (el panel los leerá vía API en la Fase 3) |
| Radicado `BGA-AAAA-NNNNNN` | MongoDB `counters` (`$inc` atómico) | API |
| Rate limit | MongoDB `rate_limits` (índice TTL) | API |
| Auditoría | MongoDB `audit_logs` (solo inserción desde código) | API |
| Personal (operador, supervisor, admin), categorías, cuadrantes, `app_settings` | Supabase (Auth + Postgres + RLS) | Panel web; la API lee categorías y ajustes con service role |
| Histórico oficial y agregados | MongoDB (sin cambios) | ETL PySpark + API |

- La app ya no incluye `supabase_flutter`. El tiempo real del ciudadano pasa a ser una consulta periódica (cada 30 s mientras la pantalla de seguimiento esté abierta) más deslizar para refrescar.
- Las reglas que antes vivían en triggers de Postgres pasan al servicio Python, con pruebas: radicado, transiciones válidas, historial inalterable, timeline público sin notas internas y token anónimo guardado solo como sha256.
- Recuperar la contraseña usa un código de 6 dígitos (sha256, 15 min, 5 intentos) enviado por SMTP (`SMTP_*`). Sin SMTP configurado, en local se escribe en el log de la API.
- Las tablas `incidents`, `evidence`, `incident_history`, `institutional_messages` y `assignments` de Postgres quedan **sin uso** hasta la Fase 3, que decide si se eliminan.

## Consecuencias
- Se pierde la RLS como barrera final para los datos ciudadanos: la autorización vive solo en la API y se cubre con pruebas de propiedad (404 uniforme).
- El tiempo real del panel en la Fase 3 necesitará *change streams* (Atlas o un replica set local) o consultas periódicas.
- Hay un secreto nuevo, `CITIZEN_JWT_SECRET`, de al menos 32 caracteres.
