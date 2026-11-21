"""ETL PySpark de AlertaBGA: datos oficiales de datos.gov.co → MongoDB (histórico y agregados).

Fuentes:
- 75fz-q98y "40Delitos ocurridos en el Municipio de Bucaramanga" (2010–2021, georreferenciado, 135.076 filas)
- x46e-abhz "Información delictiva del municipio de Bucaramanga" (2016–actualidad, por barrio/comuna, sin coordenadas)
"""

FUENTE_HISTORICO = "datos.gov.co/75fz-q98y"
FUENTE_OFICIAL = "datos.gov.co/x46e-abhz"

# Caja envolvente del municipio (incluye zona rural norte). Filtro de calidad de coordenadas, NO límite oficial:
# no separa municipios vecinos del área metropolitana; eso requiere el polígono municipal oficial (DANE MGN).
# Debe coincidir con app_settings.territorial_scope en Supabase.
BBOX = {"min_lat": 7.03, "max_lat": 7.25, "min_lon": -73.20, "max_lon": -73.03}
