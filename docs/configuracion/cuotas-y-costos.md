# Cuotas, límites y costos de proveedores

Consulta del 2026-11-21. **Verificar en las páginas oficiales antes de contratar**: los precios cambian y algunas cifras vienen de guías de terceros (marcadas con †).

| Proveedor | Plan gratuito | Plan recomendado para el piloto | Límites que afectan a AlertaBGA |
|---|---|---|---|
| **Vercel** ([planes](https://vercel.com/docs/plans/hobby)) | Hobby: **solo uso personal, no comercial**; se pausa si se exceden límites | **Pro** (≈ USD 20/usuario/mes con USD 20 de crédito de uso †). Un piloto institucional no califica como Hobby | Duración máxima de función 300 s (Pro, configurable a 800 s) ([docs](https://vercel.com/docs/functions/usage-and-pricing)). `vercel.json` fija 15 s. Bundle Python ≤ 250 MB |
| **Supabase** ([pricing](https://supabase.com/pricing)) | 500 MB de base, 50 mil MAU, 2 proyectos; **se pausa tras 7 días sin actividad** | **Pro** USD 25/mes: 8 GB de disco, 100 mil MAU, 250 GB de egreso, backups diarios con 7 días de retención | El plan gratuito no sirve para producción (pausa y sin backups). Verificar los límites de conexiones Realtime concurrentes del plan |
| **Cloudflare R2** ([pricing](https://developers.cloudflare.com/r2/pricing/)) | 10 GB-mes, 1 M operaciones clase A, 10 M clase B †, **egreso gratis** | Pago por uso: almacenamiento estándar ≈ USD 0,015/GB-mes † | Con fotos de ≤ 5 MB y 3 por reporte, 10 GB alcanzan para unas 2.000 evidencias máximas. Definir la retención (`retention_until`) |
| **MongoDB Atlas** ([pricing](https://www.mongodb.com/pricing)) | M0: 512 MB, 100 ops/s, 500 conexiones ([límites](https://www.mongodb.com/docs/atlas/reference/free-shared-limitations/)) | M0 alcanza hoy. Flex (USD 8–30/mes) si crece | El histórico ocupa ≈ 38 MB de datos (6,7 MB comprimido) + 3,8 MB de índices, medido en el ETL local. Habilitar acceso de red desde Vercel (IP dinámica) |
| **Firebase Cloud Messaging** | Gratuito | — | Solo cuando se implemente push (fase posterior) |

## Costo mensual estimado del piloto
Vercel Pro (1 asiento) + Supabase Pro + R2 dentro del gratuito + Atlas M0 ≈ **USD 45–55/mes**, más el excedente de cómputo de Supabase según la instancia.

## Riesgos de cuota
- **Supabase gratuito en producción:** la pausa por inactividad dejaría la app sin servicio. Usar Pro.
- **Arranque en frío de la función Python:** la primera petición tarda 1 a 3 s. Es aceptable para reportes; no lo es para tiempo real, que va por Supabase Realtime.
- **Atlas M0:** 100 ops/s basta para consultas de dashboard agregadas. No usarlo para escrituras masivas desde Vercel; el ETL corre fuera.
