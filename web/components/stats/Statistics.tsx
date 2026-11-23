"use client";

import { useState } from "react";
import { btn, Card, ErrorBox, field, Kpi, Skeleton } from "@/components/ui";
import { BarList, ColumnChart } from "@/components/ui/charts";
import { download, useApi } from "@/lib/api";
import {
  fmtDay,
  fmtNumber,
  PRIORITY_COLOR,
  PRIORITY_LABEL,
  SOURCE_LABEL,
  STATUS_COLOR,
  STATUS_LABEL,
  type Priority,
  type Status,
} from "@/lib/incidents";

interface Stats {
  days: number;
  total: number;
  by_status: { key: Status; count: number }[];
  by_category: { key: string; count: number }[];
  by_priority: { key: Priority; count: number }[];
  by_source: Record<string, number>;
  by_day: { date: string; count: number }[];
  by_hour: { key: number; count: number }[];
  by_weekday: { key: string; count: number }[];
  first_response_hours: { avg: number | null; median: number | null; n: number };
  resolution_hours: { avg: number | null; median: number | null; n: number };
  out_of_scope: number;
}

interface Aggregates {
  fuente: string;
  tipo_fuente: string;
  periodo: string;
  dimension: string;
  items: { clave: string; conteo: number }[];
}

const RANGES = [
  { v: 7, t: "Últimos 7 días" },
  { v: 30, t: "Últimos 30 días" },
  { v: 90, t: "Últimos 90 días" },
  { v: 365, t: "Último año" },
];

const fmtHours = (h: number | null) => (h === null ? "—" : h < 1 ? `${Math.round(h * 60)} min` : h < 48 ? `${h.toFixed(1)} h` : `${(h / 24).toFixed(1)} d`);

function Historic() {
  const [fuente, setFuente] = useState<"historico" | "oficial">("historico");
  const [dimension, setDimension] = useState("anio");
  const dims = fuente === "historico"
    ? [["anio", "Por año"], ["categoria", "Por delito"], ["comuna", "Por comuna"], ["barrio", "Top barrios"]]
    : [["anio", "Por año"], ["anio_mes", "Por mes"], ["categoria", "Por delito"]];
  const valid = dims.some(([d]) => d === dimension) ? dimension : "anio";
  const limit = valid === "anio_mes" ? 500 : valid === "barrio" ? 15 : 30;
  const { data, error, loading } = useApi<Aggregates>(`/historico/agregados?fuente=${fuente}&dimension=${valid}&limite=${limit}`);
  const series = valid === "anio" || valid === "anio_mes";
  const items = data?.items ?? [];
  const shown = valid === "anio_mes" ? items.slice(-36) : items;

  return (
    <Card title="Histórico institucional (referencia, no son reportes de la plataforma)">
      <div className="mb-4 flex flex-wrap gap-2">
        <select aria-label="Fuente" className={`${field} max-w-xs`} value={fuente} onChange={(e) => setFuente(e.target.value as "historico" | "oficial")}>
          <option value="historico">Delitos georreferenciados 2010–2021</option>
          <option value="oficial">Estadística oficial agregada 2016–2026</option>
        </select>
        <div role="tablist" className="flex flex-wrap gap-1">
          {dims.map(([d, t]) => (
            <button key={d} role="tab" aria-selected={valid === d} onClick={() => setDimension(d)}
              className={`rounded-lg px-3 py-1.5 text-xs font-semibold ${valid === d ? "bg-navy-900 text-white" : "border border-line text-navy-900 hover:bg-bg"}`}>
              {t}
            </button>
          ))}
        </div>
      </div>
      {error && <ErrorBox message={error.message} />}
      {loading && <Skeleton className="h-48" />}
      {data && (
        <>
          {series ? (
            <ColumnChart ariaLabel="Histórico" color="#1D4278" labelEvery={Math.max(1, Math.ceil(shown.length / 12))}
              data={shown.map((i) => ({ label: i.clave, value: i.conteo }))} />
          ) : (
            <BarList color="#1D4278" items={shown.map((i) => ({ key: i.clave.toLowerCase(), count: i.conteo }))} />
          )}
          <p className="mt-3 text-[11px] text-muted">
            Fuente: {data.fuente} · {data.tipo_fuente} · periodo {data.periodo}
            {valid === "anio_mes" && " · últimos 36 meses"}
          </p>
        </>
      )}
    </Card>
  );
}

export function Statistics() {
  const [days, setDays] = useState(30);
  const { data: s, error, loading, reload } = useApi<Stats>(`/staff/stats?days=${days}`);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <select aria-label="Periodo" className={`${field} max-w-xs`} value={days} onChange={(e) => setDays(Number(e.target.value))}>
          {RANGES.map((r) => <option key={r.v} value={r.v}>{r.t}</option>)}
        </select>
        <button className={btn.secondary} onClick={() => download(`/staff/incidents.csv?days=${days}`, `alertabga-incidentes-${days}d.csv`)}>
          Exportar reportes del periodo (CSV)
        </button>
      </div>

      {error && !s && <ErrorBox message={error.message} onRetry={reload} />}
      {loading && !s && <Skeleton className="h-96" />}

      {s && (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <Kpi label="Reportes recibidos" value={fmtNumber(s.total)} hint={`${s.out_of_scope} fuera del ámbito`} />
            <Kpi label="Primera gestión (mediana)" value={fmtHours(s.first_response_hours.median)}
              hint={`promedio ${fmtHours(s.first_response_hours.avg)} · ${s.first_response_hours.n} casos`} />
            <Kpi label="Tiempo de cierre (mediana)" value={fmtHours(s.resolution_hours.median)}
              hint={`promedio ${fmtHours(s.resolution_hours.avg)} · ${s.resolution_hours.n} cerrados`} tone="ok" />
            <Kpi label="Anónimos / con cuenta"
              value={`${s.by_source.APP_ANONIMO ?? 0} / ${s.by_source.APP_AUTENTICADO ?? 0}`}
              hint={Object.keys(s.by_source).map((k) => SOURCE_LABEL[k] ?? k).join(" · ") || "sin datos"} />
          </div>

          <Card title="Reportes por día">
            <ColumnChart ariaLabel="Reportes por día" labelEvery={Math.max(1, Math.ceil(s.by_day.length / 15))}
              data={s.by_day.map((d) => ({ label: fmtDay(d.date), value: d.count }))} />
          </Card>

          <div className="grid gap-4 lg:grid-cols-3">
            <Card title="Por categoría"><BarList items={s.by_category} /></Card>
            <Card title="Por estado">
              <BarList items={s.by_status.map((i) => ({ key: STATUS_LABEL[i.key] ?? i.key, count: i.count, color: STATUS_COLOR[i.key] }))} />
            </Card>
            <Card title="Por prioridad">
              <BarList items={s.by_priority.map((i) => ({ key: PRIORITY_LABEL[i.key] ?? i.key, count: i.count, color: PRIORITY_COLOR[i.key] }))} />
            </Card>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card title="Hora del día en que llegan (Bogotá)">
              <ColumnChart ariaLabel="Reportes por hora" color="#13305A" labelEvery={3}
                data={s.by_hour.map((h) => ({ label: `${h.key}h`, value: h.count }))} />
            </Card>
            <Card title="Día de la semana">
              <ColumnChart ariaLabel="Reportes por día de la semana" color="#13305A"
                data={s.by_weekday.map((d) => ({ label: d.key.slice(0, 3), value: d.count }))} />
            </Card>
          </div>
        </>
      )}

      <Historic />
    </div>
  );
}
