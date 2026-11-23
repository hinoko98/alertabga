"use client";

import Link from "next/link";
import { isManager, useStaff } from "@/components/layout/SessionProvider";
import { Card, Empty, ErrorBox, Kpi, PriorityBadge, Skeleton, StatusBadge } from "@/components/ui";
import { BarList, ColumnChart, Donut } from "@/components/ui/charts";
import { useApi } from "@/lib/api";
import {
  fmtDay,
  OPEN_STATUSES,
  STATUS_COLOR,
  STATUS_LABEL,
  timeAgo,
  type IncidentRow,
  type Status,
} from "@/lib/incidents";

interface Summary {
  open_total: number;
  by_status: Record<Status, number>;
  unassigned_open: number;
  mine_open: number;
  high_priority_open: number;
  today: number;
  last_14_days: { date: string; count: number }[];
  top_categories_30d: { key: string; count: number }[];
  avg_first_response_min: number | null;
  recent: IncidentRow[];
  generated_at: string;
}

function fmtMinutes(min: number | null) {
  if (min === null) return "—";
  if (min < 60) return `${Math.round(min)} min`;
  return `${(min / 60).toFixed(1)} h`;
}

export function Dashboard() {
  const staff = useStaff();
  const { data, error, loading, reload } = useApi<Summary>("/staff/summary", 20_000);

  if (error && !data) return <ErrorBox message={error.message} onRetry={reload} />;
  if (loading || !data)
    return (
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className={i < 4 ? "h-28" : "h-64 xl:col-span-2"} />)}
      </div>
    );

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted">
          Hola, <span className="font-semibold text-ink">{staff.fullName ?? staff.email}</span>. Se actualiza cada 20 s ·
          última actualización {new Date(data.generated_at).toLocaleTimeString("es-CO")}
        </p>
        <Link href="/incidentes" className="text-sm font-semibold text-navy-700 hover:underline">Ir a la bandeja →</Link>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <Kpi label="Reportes abiertos" value={data.open_total} href="/incidentes" />
        <Kpi label="Recibidos hoy" value={data.today} hint="Hora de Bogotá" />
        <Kpi label="Sin asignar" value={data.unassigned_open} tone={data.unassigned_open ? "alert" : "ok"}
          href="/incidentes?assigned=none" />
        <Kpi label={isManager(staff.role) ? "Asignados a mí" : "Mis casos abiertos"} value={data.mine_open}
          href="/incidentes?assigned=me" />
        <Kpi label="Prioridad alta o crítica" value={data.high_priority_open}
          tone={data.high_priority_open ? "danger" : "ok"} hint={`1.ª respuesta prom.: ${fmtMinutes(data.avg_first_response_min)}`} />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Card title="Reportes recibidos · últimos 14 días" className="xl:col-span-2">
          <ColumnChart ariaLabel="Reportes por día" labelEvery={2}
            data={data.last_14_days.map((d) => ({ label: fmtDay(d.date), value: d.count }))} />
        </Card>
        <Card title="Abiertos por estado">
          <Donut items={OPEN_STATUSES.map((s) => ({ key: s, label: STATUS_LABEL[s], count: data.by_status[s] ?? 0,
            color: STATUS_COLOR[s] }))} />
        </Card>
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Card title="Últimos reportes" className="xl:col-span-2"
          action={<Link href="/incidentes" className="text-xs font-semibold text-navy-700 hover:underline">Ver todos</Link>}>
          {data.recent.length === 0 ? (
            <Empty>Aún no hay reportes ciudadanos.</Empty>
          ) : (
            <ul className="divide-y divide-line">
              {data.recent.map((r) => (
                <li key={r.radicado}>
                  <Link href={`/incidentes/${r.radicado}`} className="flex flex-wrap items-center gap-x-4 gap-y-1 py-2.5 hover:bg-bg">
                    <span className="font-mono text-xs font-semibold text-navy-900">{r.radicado}</span>
                    <span className="min-w-28 flex-1 truncate text-sm text-ink">{r.category}</span>
                    <PriorityBadge priority={r.priority} />
                    <StatusBadge status={r.status} />
                    <span className="w-24 text-right text-xs text-muted">{timeAgo(r.received_at)}</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card title="Categorías · últimos 30 días">
          <BarList items={data.top_categories_30d} />
        </Card>
      </div>
    </div>
  );
}
