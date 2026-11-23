# Fase 3 — Panel institucional (panel, mapa, bandeja, estadísticas, administración)

El usuario delegó las decisiones. Este documento las registra.

## Alcance
| Sección | Ruta | Roles | Contenido |
|---|---|---|---|
| Panel principal | `/` | operador, supervisor, admin | KPIs en vivo (abiertos, hoy, sin asignar, míos, prioridad alta), serie de 14 días, categorías de 30 días, últimos reportes |
| Mapa territorial | `/mapa` | operador, supervisor, admin | Reportes recientes por estado, calor de reportes, calor del histórico oficial 2010–2021 (etiquetado), filtros |
| Bandeja | `/incidentes` | operador, supervisor, admin | Filtros (estado, categoría, prioridad, asignación, texto, fechas), paginación, actualización cada 20 s |
| Detalle | `/incidentes/[radicado]` | operador, supervisor, admin | Datos, ubicación, fotos (URL firmada), reportante, historial completo, acciones |
| Estadísticas | `/estadisticas` | supervisor, admin | Operativas por rango (estado, categoría, día, hora, día de semana, tiempos de respuesta), histórico oficial, exportación CSV |
| Administración | `/administracion` | admin | Usuarios del personal, categorías, ajustes (límite de reportes), auditoría |
| Estado de la plataforma | `/estado` | operador, supervisor, admin | Lo que antes estaba en `/` |

## Decisiones
1. **Datos:** los incidentes se leen y gestionan en MongoDB a través de la API (ADR 0003). Las tablas `incidents`, `evidence`, `incident_history`, `institutional_messages` y `assignments` de Postgres siguen sin uso; no se eliminan en esta fase para no romper las pruebas pgTAP existentes.
2. **Visibilidad:** no hay polígonos oficiales de cuadrantes, así que todo el personal ve todos los incidentes del municipio. La bandeja abre en la vista "Abiertos", con pestañas rápidas "Sin asignar", "Asignados a mí", "Cerrados" y "Todos".
3. **Permisos de gestión:**
   - Operador: puede **tomar** un incidente sin asignar y gestionar (estado, prioridad, notas) solo los que tiene asignados.
   - Supervisor y administrador: asignan a cualquier miembro activo del personal y gestionan cualquier incidente; pueden reabrir uno cerrado.
4. **Estados** (spec §6): `RECIBIDO → EN_REVISION | ASIGNADO | NO_PROCEDE`; `EN_REVISION → ASIGNADO | NO_PROCEDE`; `ASIGNADO → EN_ATENCION | EN_REVISION | NO_PROCEDE`; `EN_ATENCION → CERRADO | ASIGNADO`; `CERRADO | NO_PROCEDE → EN_REVISION` (reabrir, solo supervisor/admin). Cerrar o marcar "no procede" exige un mensaje para el ciudadano.
5. **Historial:** cada cambio de estado escribe una entrada pública con un texto genérico (o el mensaje escrito). Notas internas, asignaciones (con el nombre del funcionario) y prioridad son entradas **internas**: el ciudadano nunca ve nombres de funcionarios.
6. **Auditoría:** toda acción del personal, la vista del detalle y la exportación quedan en `audit_logs` (MongoDB).
7. **Tiempo real:** consultas periódicas (panel y bandeja cada 20 s). Los *change streams* requieren replica set; se dejan para producción con Atlas.
8. **Mapa:** Leaflet + OpenStreetMap (solo desarrollo; revisar términos antes de producción, spec §10). El calor histórico agrega las 127.754 coordenadas en celdas de ~110 m.
9. **Gráficas:** SVG propio, sin librerías.
10. **Exportación CSV:** sin datos personales del reportante; celdas que empiezan por `= + - @` se neutralizan (inyección de fórmulas).
11. **Administración:** perfiles, categorías y ajustes se modifican con el **token del administrador**, así la RLS y el trigger `protect_profile_privileges` siguen siendo la barrera final. La clave de servicio solo se usa para crear cuentas en Supabase Auth y leer correos. Un administrador no puede quitarse su propio rol ni desactivarse.

## Verificación
- pytest: flujo de estados, permisos por rol, historial público sin notas internas, resúmenes, CSV, administración.
- lint + tsc del panel.
- Recorrido manual en el navegador con administrador y operador (ver `docs/GUIA-PRUEBAS.md`).

## Datos de demostración
`web/scripts/sembrar_demo.py` inserta reportes `BGA-DEMO-*` (marcados `demo: true`) en el MongoDB local; `--borrar` los elimina.
