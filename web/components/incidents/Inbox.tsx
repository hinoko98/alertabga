"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import { isManager, useStaff } from "@/components/layout/SessionProvider";
import { btn, Empty, ErrorBox, field, PriorityBadge, Skeleton, StatusBadge } from "@/components/ui";
import { download, useApi } from "@/lib/api";
import {
  fmtDateTime,
  fmtNumber,
  PRIORITIES,
  PRIORITY_LABEL,
  STATUSES,
  STATUS_LABEL,
  timeAgo,
  type Category,
  type IncidentRow,
  type Page,
} from "@/lib/incidents";

const TABS = [
  { id: "abiertos", label: "Abiertos", params: { status: "RECIBIDO,EN_REVISION,ASIGNADO,EN_ATENCION" } },
  { id: "sin", label: "Sin asignar", params: { status: "RECIBIDO,EN_REVISION", assigned: "none" } },
  { id: "mios", label: "Asignados a mí", params: { assigned: "me", status: "ASIGNADO,EN_ATENCION,EN_REVISION" } },
  { id: "cerrados", label: "Cerrados", params: { status: "CERRADO,NO_PROCEDE" } },
  { id: "todos", label: "Todos", params: {} },
] as const;

const FILTER_KEYS = ["status", "assigned", "category_id", "priority", "q", "from", "to"] as const;

export function Inbox() {
  const staff = useStaff();
  const router = useRouter();
  const pathname = usePathname();
  const sp = useSearchParams();
  const [q, setQ] = useState(sp.get("q") ?? "");

  // Sin parámetros: pestaña "Abiertos".
  // Un parámetro presente pero vacío (p. ej. `status=`) significa "todos".
  const hasFilters = FILTER_KEYS.some((k) => sp.has(k));
  const effective = useMemo(() => {
    const p = new URLSearchParams(sp.toString());
    if (!hasFilters) p.set("status", TABS[0].params.status);
    for (const k of FILTER_KEYS) if (p.has(k) && !p.get(k)) p.delete(k);
    if (!p.get("page_size")) p.set("page_size", "25");
    return p;
  }, [sp, hasFilters]);

  const { data, error, loading, reload } = useApi<Page<IncidentRow>>(`/staff/incidents?${effective}`, 20_000);
  const categories = useApi<Category[]>("/categories");

  function update(values: Record<string, string | null>, resetPage = true) {
    const p = new URLSearchParams(sp.toString());
    if (!hasFilters && !("status" in values)) p.set("status", TABS[0].params.status);
    for (const [k, v] of Object.entries(values)) {
      if (v) p.set(k, v);
      else if (k === "status") p.set(k, "");
      else p.delete(k);
    }
    if (resetPage) p.delete("page");
    router.replace(`${pathname}?${p}`, { scroll: false });
  }

  function selectTab(params: Record<string, string>) {
    setQ("");
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) p.set(k, v);
    if (Object.keys(params).length === 0) p.set("status", "");
    router.replace(`${pathname}?${p}`, { scroll: false });
  }

  const activeTab = TABS.find((t) => {
    const want = t.params as Record<string, string>;
    const keys = ["status", "assigned"];
    return keys.every((k) => (effective.get(k) ?? "") === (want[k] ?? "")) &&
      !["category_id", "priority", "q", "from", "to"].some((k) => sp.get(k));
  })?.id;

  const page = Number(effective.get("page") ?? 1);
  const pages = data ? Math.max(1, Math.ceil(data.total / data.page_size)) : 1;
  const exportQuery = new URLSearchParams(effective);
  exportQuery.delete("page");
  exportQuery.delete("page_size");

  return (
    <div className="space-y-4">
      <div role="tablist" aria-label="Vistas de la bandeja" className="flex flex-wrap gap-1 rounded-xl border border-line bg-surface p-1">
        {TABS.map((t) => (
          <button key={t.id} role="tab" aria-selected={activeTab === t.id} onClick={() => selectTab(t.params)}
            className={`rounded-lg px-3.5 py-1.5 text-sm font-semibold transition ${
              activeTab === t.id ? "bg-navy-900 text-white" : "text-navy-900 hover:bg-bg"}`}>
            {t.label}
          </button>
        ))}
      </div>

      <form className="grid gap-3 rounded-xl border border-line bg-surface p-4 md:grid-cols-6"
        onSubmit={(e) => { e.preventDefault(); update({ q: q.trim() || null }); }}>
        <div className="md:col-span-2">
          <label htmlFor="q" className="sr-only">Buscar</label>
          <input id="q" value={q} onChange={(e) => setQ(e.target.value)} className={field}
            placeholder="Buscar radicado, descripción o dirección" maxLength={80} />
        </div>
        <select aria-label="Estado" className={field} value={sp.get("status")?.includes(",") ? "" : (sp.get("status") ?? "")}
          onChange={(e) => update({ status: e.target.value || null })}>
          <option value="">Todos los estados</option>
          {STATUSES.map((s) => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}
        </select>
        <select aria-label="Categoría" className={field} value={sp.get("category_id") ?? ""}
          onChange={(e) => update({ category_id: e.target.value || null })}>
          <option value="">Todas las categorías</option>
          {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select aria-label="Prioridad" className={field} value={sp.get("priority") ?? ""}
          onChange={(e) => update({ priority: e.target.value || null })}>
          <option value="">Toda prioridad</option>
          {PRIORITIES.map((p) => <option key={p} value={p}>{PRIORITY_LABEL[p]}</option>)}
        </select>
        <div className="flex gap-2">
          <button type="submit" className={`${btn.primary} flex-1`}>Buscar</button>
          {(sp.toString() !== "" || q) && (
            <button type="button" className={btn.secondary} onClick={() => { setQ(""); router.replace(pathname); }}
              title="Limpiar filtros">✕</button>
          )}
        </div>
        <div className="flex items-center gap-2 md:col-span-3">
          <label htmlFor="from" className="text-xs font-semibold text-muted">Desde</label>
          <input id="from" type="date" className={field} value={sp.get("from") ?? ""} onChange={(e) => update({ from: e.target.value || null })} />
          <label htmlFor="to" className="text-xs font-semibold text-muted">Hasta</label>
          <input id="to" type="date" className={field} value={sp.get("to") ?? ""} onChange={(e) => update({ to: e.target.value || null })} />
        </div>
        <div className="flex items-center justify-end gap-3 md:col-span-3">
          {data && <span className="text-sm text-muted">{fmtNumber(data.total)} reporte(s)</span>}
          {isManager(staff.role) && (
            <button type="button" className={btn.secondary}
              onClick={() => download(`/staff/incidents.csv?${exportQuery}`, "alertabga-incidentes.csv")}>
              Exportar CSV
            </button>
          )}
        </div>
      </form>

      {error && !data && <ErrorBox message={error.message} onRetry={reload} />}
      {loading && !data && <Skeleton className="h-96" />}

      {data && (
        <div className="overflow-hidden rounded-xl border border-line bg-surface">
          {data.items.length === 0 ? (
            <Empty>No hay reportes con estos filtros.</Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[860px] text-sm">
                <thead className="border-b border-line bg-bg text-left text-xs uppercase tracking-wide text-muted">
                  <tr>
                    <th scope="col" className="px-4 py-3 font-semibold">Radicado</th>
                    <th scope="col" className="px-4 py-3 font-semibold">Recibido</th>
                    <th scope="col" className="px-4 py-3 font-semibold">Categoría</th>
                    <th scope="col" className="px-4 py-3 font-semibold">Estado</th>
                    <th scope="col" className="px-4 py-3 font-semibold">Prioridad</th>
                    <th scope="col" className="px-4 py-3 font-semibold">Asignado a</th>
                    <th scope="col" className="px-4 py-3 font-semibold">Origen</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-line">
                  {data.items.map((r) => (
                    <tr key={r.radicado} className="cursor-pointer hover:bg-bg" onClick={() => router.push(`/incidentes/${r.radicado}`)}>
                      <td className="px-4 py-3">
                        <Link href={`/incidentes/${r.radicado}`} className="font-mono text-xs font-semibold text-navy-900 hover:underline"
                          onClick={(e) => e.stopPropagation()}>
                          {r.radicado}
                        </Link>
                        {r.demo && <span className="ml-2 rounded bg-slate-200 px-1.5 py-0.5 text-[10px] font-bold text-slate-600" title="Dato de demostración, no viene de la app">DEMO</span>}
                        {r.out_of_scope && <span className="ml-2 rounded bg-alert/15 px-1.5 py-0.5 text-[10px] font-bold text-alert">FUERA DE ÁMBITO</span>}
                      </td>
                      <td className="px-4 py-3">
                        <span className="block text-ink">{timeAgo(r.received_at)}</span>
                        <span className="text-xs text-muted">{fmtDateTime(r.received_at)}</span>
                      </td>
                      <td className="px-4 py-3 text-ink">{r.category}</td>
                      <td className="px-4 py-3"><StatusBadge status={r.status} /></td>
                      <td className="px-4 py-3"><PriorityBadge priority={r.priority} /></td>
                      <td className="px-4 py-3 text-ink">{r.assigned_name ?? <span className="text-muted">Sin asignar</span>}</td>
                      <td className="px-4 py-3 text-xs text-muted">{r.demo ? "Demostración" : r.source === "APP_ANONIMO" ? "App · anónimo" : "App · con cuenta"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {pages > 1 && (
            <nav aria-label="Paginación" className="flex items-center justify-between border-t border-line px-4 py-3 text-sm">
              <button className={btn.secondary} disabled={page <= 1} onClick={() => update({ page: String(page - 1) }, false)}>
                ← Anterior
              </button>
              <span className="text-muted">Página {page} de {pages}</span>
              <button className={btn.secondary} disabled={page >= pages} onClick={() => update({ page: String(page + 1) }, false)}>
                Siguiente →
              </button>
            </nav>
          )}
        </div>
      )}
    </div>
  );
}
