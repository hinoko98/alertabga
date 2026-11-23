"use client";

import { useMemo, useState } from "react";
import { ErrorBox, field, label } from "@/components/ui";
import { useApi } from "@/lib/api";
import { fmtNumber, STATUSES, STATUS_COLOR, STATUS_LABEL, type Category } from "@/lib/incidents";
import { IncidentMap, type MapPoint } from "./index";

interface Heat {
  periodo: string;
  fuente: string;
  total: number;
  max: number;
  puntos: [number, number, number][];
  advertencia: string;
}

const RANGES = [
  { v: 1, t: "Últimas 24 h" },
  { v: 7, t: "7 días" },
  { v: 30, t: "30 días" },
  { v: 90, t: "90 días" },
  { v: 365, t: "1 año" },
];

function Toggle({ checked, onChange, children }: { checked: boolean; onChange: (v: boolean) => void; children: React.ReactNode }) {
  return (
    <label className="flex cursor-pointer items-center gap-2 text-sm text-ink">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="size-4 accent-navy-900" />
      {children}
    </label>
  );
}

export function TerritorialMap() {
  const [days, setDays] = useState(30);
  const [scope, setScope] = useState<"open" | "all">("open");
  const [category, setCategory] = useState("");
  const [markers, setMarkers] = useState(true);
  const [heat, setHeat] = useState(false);
  const [historic, setHistoric] = useState(false);
  const [from, setFrom] = useState(2019);
  const [to, setTo] = useState(2021);
  const [histCat, setHistCat] = useState("");

  const q = new URLSearchParams({ days: String(days) });
  if (scope === "open") q.set("status", "RECIBIDO,EN_REVISION,ASIGNADO,EN_ATENCION");
  if (category) q.set("category_id", category);
  const points = useApi<{ points: MapPoint[]; truncated: boolean }>(`/staff/map?${q}`, 30_000);
  const categories = useApi<Category[]>("/categories");
  const histCats = useApi<string[]>(historic ? "/historico/categorias" : null);
  const hq = new URLSearchParams({ desde: String(Math.min(from, to)), hasta: String(Math.max(from, to)) });
  if (histCat) hq.set("categoria", histCat);
  const heatData = useApi<Heat>(historic ? `/historico/calor?${hq}` : null);

  const pts = useMemo(() => points.data?.points ?? [], [points.data]);
  const counts = useMemo(() => {
    const c: Record<string, number> = {};
    for (const p of pts) c[p.status] = (c[p.status] ?? 0) + 1;
    return c;
  }, [pts]);
  const histHeat = useMemo(
    () => (historic && heatData.data ? { points: heatData.data.puntos, max: heatData.data.max } : null),
    [historic, heatData.data],
  );

  return (
    <div className="grid gap-4 xl:grid-cols-[300px_1fr]">
      <aside className="space-y-5 rounded-xl border border-line bg-surface p-4">
        <section className="space-y-3">
          <h2 className="text-sm font-bold text-navy-900">Reportes ciudadanos</h2>
          <div>
            <label htmlFor="days" className={label}>Periodo</label>
            <select id="days" className={field} value={days} onChange={(e) => setDays(Number(e.target.value))}>
              {RANGES.map((r) => <option key={r.v} value={r.v}>{r.t}</option>)}
            </select>
          </div>
          <div>
            <label htmlFor="scope" className={label}>Estados</label>
            <select id="scope" className={field} value={scope} onChange={(e) => setScope(e.target.value as "open" | "all")}>
              <option value="open">Solo abiertos</option>
              <option value="all">Todos (incluye cerrados)</option>
            </select>
          </div>
          <div>
            <label htmlFor="cat" className={label}>Categoría</label>
            <select id="cat" className={field} value={category} onChange={(e) => setCategory(e.target.value)}>
              <option value="">Todas</option>
              {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <Toggle checked={markers} onChange={setMarkers}>Puntos por estado</Toggle>
          <Toggle checked={heat} onChange={setHeat}>Mapa de calor de reportes</Toggle>
          <p className="text-xs text-muted">{fmtNumber(pts.length)} reporte(s) en el mapa · se actualiza cada 30 s</p>
          <ul className="space-y-1 text-xs">
            {STATUSES.map((s) => (
              <li key={s} className="flex items-center gap-2">
                <span aria-hidden className="size-3 rounded-full border border-white shadow" style={{ backgroundColor: STATUS_COLOR[s] }} />
                <span className="flex-1">{STATUS_LABEL[s]}</span>
                <span className="font-mono text-muted">{counts[s] ?? 0}</span>
              </li>
            ))}
          </ul>
        </section>

        <section className="space-y-3 border-t border-line pt-4">
          <h2 className="text-sm font-bold text-navy-900">Referencia histórica oficial</h2>
          <Toggle checked={historic} onChange={setHistoric}>Calor de delitos 2010–2021</Toggle>
          {historic && (
            <>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label htmlFor="from" className={label}>Desde</label>
                  <select id="from" className={field} value={from} onChange={(e) => setFrom(Number(e.target.value))}>
                    {Array.from({ length: 12 }, (_, i) => 2010 + i).map((y) => <option key={y}>{y}</option>)}
                  </select>
                </div>
                <div>
                  <label htmlFor="to" className={label}>Hasta</label>
                  <select id="to" className={field} value={to} onChange={(e) => setTo(Number(e.target.value))}>
                    {Array.from({ length: 12 }, (_, i) => 2010 + i).map((y) => <option key={y}>{y}</option>)}
                  </select>
                </div>
              </div>
              <div>
                <label htmlFor="hcat" className={label}>Delito</label>
                <select id="hcat" className={field} value={histCat} onChange={(e) => setHistCat(e.target.value)}>
                  <option value="">Todos</option>
                  {histCats.data?.map((c) => <option key={c} value={c}>{c.toLowerCase()}</option>)}
                </select>
              </div>
              {heatData.loading && <p className="text-xs text-muted">Calculando…</p>}
              {heatData.data && (
                <p className="rounded-lg bg-bg p-2.5 text-[11px] leading-relaxed text-muted">
                  {fmtNumber(heatData.data.total)} delitos · {heatData.data.periodo} · fuente {heatData.data.fuente}.{" "}
                  {heatData.data.advertencia}
                </p>
              )}
              {heatData.error && <p className="text-xs text-danger">{heatData.error.message}</p>}
            </>
          )}
        </section>
      </aside>

      <div className="space-y-3">
        {points.error && <ErrorBox message={points.error.message} onRetry={points.reload} />}
        {points.data?.truncated && <p className="text-xs text-alert">Se muestran los 5.000 reportes más recientes. Acote el periodo.</p>}
        <div className="overflow-hidden rounded-xl border border-line">
          <IncidentMap points={pts} showMarkers={markers} heat={heat} historicHeat={histHeat} height="calc(100dvh - 190px)" />
        </div>
        <p className="text-[11px] text-muted">
          Mapa base © OpenStreetMap (uso de desarrollo; revisar términos del proveedor antes de producción). Aún no hay
          polígonos oficiales de cuadrantes.
        </p>
      </div>
    </div>
  );
}
