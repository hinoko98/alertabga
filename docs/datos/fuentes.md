# Fuentes de datos institucionales

Investigación realizada el 2026-11-21. Solo se registra lo verificado; lo que no se encontró queda indicado como pendiente.

## 1. Histórico georreferenciado 2010–2021 (línea base de la entrega académica)

| Campo | Valor |
|---|---|
| Dataset | "40Delitos ocurridos en el Municipio de Bucaramanga" |
| Identificador | `75fz-q98y` — https://www.datos.gov.co/d/75fz-q98y |
| Publicador | Alcaldía de Bucaramanga |
| Licencia | CC BY-SA 4.0 |
| Filas | 135.076 (coincide con la entrega académica) · 19 columnas |
| Periodo | 2010–2021 |
| Coordenadas | `latitud`/`longitud` como texto con separadores de miles (`"7,170,557,382"`). Se reconstruyen con `parse_coordenada` |
| Destino | MongoDB `historical_crimes` (registro limpio con GeoJSON) y `crime_aggregates` (`tipo_fuente = HISTORICO_GEORREFERENCIADO`, `periodo = "2010-2021"`) |

**Resultado del ETL (2026-11-21):** 127.754 registros con coordenadas válidas dentro del ámbito (94,58 %).

La entrega académica reporta 125.108 (92,6 %). La diferencia (+2.646) se explica porque el filtro actual es una caja envolvente del municipio y no el polígono oficial. El orden de los barrios con más registros coincide con el estudio: Centro, San Francisco, Cabecera del Llano, La Concordia. Los conteos absolutos (p. ej. Centro 10.735 frente a 11.199) difieren porque el estudio contó antes del filtro de coordenadas.

## 2. Datos oficiales recientes (reemplazan la limitación "solo hasta 2021")

| Campo | Valor |
|---|---|
| Dataset | "Información delictiva del municipio de Bucaramanga" |
| Identificador | `x46e-abhz` — https://www.datos.gov.co/d/x46e-abhz |
| Publicador | Alcaldía de Bucaramanga, Secretaría del Interior (fuente primaria SIEDCO, Policía Nacional) |
| Licencia | CC BY-SA 4.0 |
| Filas | 268.995 · actualizado 2026-11-20 |
| Periodo | 2016-01-01 a 2026-09-30 |
| Granularidad | Barrio y comuna, fecha y hora. **Sin coordenadas** |
| Destino | MongoDB `crime_aggregates` (`tipo_fuente = OFICIAL_AGREGADO`, `periodo = "2016-01..2026-09"`) |

**Uso permitido en la interfaz:** como información institucional por barrio, comuna, categoría y mes, siempre con su periodo de corte. No sirve para mapas de puntos ni para mapas de calor (no tiene coordenadas). No representa "el mes actual": su corte va unos dos meses atrás.

Complemento: la Secretaría del Interior publica boletines mensuales en PDF (p. ej. [boletín 2026-06](https://www.bucaramanga.gov.co/wp-content/uploads/2026/08/BOLETÍN-MENSUAL-DELITOS_202606.pdf)). Son útiles para validar cifras, pero no se procesan automáticamente.

## 3. Cuadrantes de Policía (MNVCC)

**No se encontró publicación abierta** de polígonos, número de cuadrantes, personal ni capacidad de cobertura de la Policía Metropolitana de Bucaramanga (MEBUC):
- No hay dataset de cuadrantes en datos.gov.co ni en el portal https://www.bucaramanga.gov.co/datos/.
- Medellín sí publica su capa de cuadrantes (servidor ArcGIS municipal), lo que muestra que el formato es viable, pero no aplica a Bucaramanga.
- El Área Metropolitana de Bucaramanga (AMB) publica cartografía catastral, que no son límites policiales.

**Decisión (sin inventar límites):**
- `quadrants.boundary` permanece nulo y la asignación es manual (cola sin cuadrante, visible al supervisor).
- El esquema ya admite cargar `MultiPolygon` con `boundary_source` obligatorio, `staff_count` y `contact_ref`. Al cargar polígonos oficiales, `assign_quadrant()` empieza a asignar automáticamente sin cambiar código.
- Acción institucional: solicitar formalmente a la MEBUC la capa de cuadrantes (GeoJSON o shapefile), su codificación oficial, el personal por turno y los contactos. Base: convenio de piloto y Ley 1712 de 2014 (transparencia), con las reservas de seguridad que apliquen.

## 4. Límite municipal

El ámbito territorial actual es una caja envolvente (lat 7.03–7.25, lon −73.20 – −73.03), marcada `official: false`. No separa Bucaramanga de Floridablanca ni de Girón. Mejora pendiente: cargar el polígono municipal del Marco Geoestadístico Nacional del DANE, que es fuente oficial.
