"use client";

import Link from "next/link";
import { useState, type FormEvent, type ReactNode } from "react";
import { IncidentMap } from "@/components/map";
import { btn, Card, ErrorBox, field, label, PriorityBadge, Skeleton, StatusBadge } from "@/components/ui";
import { ApiError, post, useApi } from "@/lib/api";
import {
  ACTION_LABEL,
  fmtDateTime,
  PRIORITIES,
  PRIORITY_LABEL,
  SOURCE_LABEL,
  STATUS_COLOR,
  STATUS_LABEL,
  timeAgo,
  type IncidentDetail as Detail,
  type Status,
  type TeamMember,
} from "@/lib/incidents";

const NEEDS_MESSAGE = (from: Status, to: Status) =>
  to === "CERRADO" || to === "NO_PROCEDE" || from === "CERRADO" || from === "NO_PROCEDE";

function Row({ k, children }: { k: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[9rem_1fr] gap-3 py-1.5 text-sm">
      <dt className="text-muted">{k}</dt>
      <dd className="text-ink">{children}</dd>
    </div>
  );
}

/** Ejecuta una acción, muestra el error en español y recarga la ficha. */
function useAction(reload: () => Promise<void> | void) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  async function run(fn: () => Promise<unknown>, success: string) {
    setBusy(true);
    setError(null);
    setOk(null);
    try {
      await fn();
      setOk(success);
      await reload();
      return true;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "No se pudo completar la acción.");
      return false;
    } finally {
      setBusy(false);
    }
  }
  return { busy, error, ok, run };
}

function Feedback({ error, ok }: { error: string | null; ok: string | null }) {
  if (error) return <p role="alert" className="text-sm text-danger">{error}</p>;
  if (ok) return <p role="status" className="text-sm text-ok">{ok}</p>;
  return null;
}

function StatusForm({ d, reload }: { d: Detail; reload: () => Promise<void> }) {
  const [to, setTo] = useState<Status | "">("");
  const [message, setMessage] = useState("");
  const [note, setNote] = useState("");
  const a = useAction(reload);
  const options = d.permissions.transitions.filter((s) => s !== "ASIGNADO" || d.assigned_to);
  if (options.length === 0) return null;
  const required = to !== "" && NEEDS_MESSAGE(d.status, to);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!to) return;
    const done = await a.run(
      () => post(`/staff/incidents/${d.radicado}/status`, { status: to, public_message: message || null, internal_note: note || null }),
      `Estado actualizado a «${STATUS_LABEL[to]}».`,
    );
    if (done) {
      setTo("");
      setMessage("");
      setNote("");
    }
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <div>
        <span className={label}>Cambiar estado</span>
        <div className="flex flex-wrap gap-2">
          {options.map((s) => (
            <button key={s} type="button" onClick={() => setTo(s)} aria-pressed={to === s}
              className="rounded-lg border px-3 py-1.5 text-xs font-semibold transition"
              style={to === s ? { backgroundColor: STATUS_COLOR[s], borderColor: STATUS_COLOR[s], color: "#fff" }
                : { borderColor: `${STATUS_COLOR[s]}66`, color: STATUS_COLOR[s] }}>
              {d.status === "CERRADO" || d.status === "NO_PROCEDE" ? "Reabrir · " : ""}{STATUS_LABEL[s]}
            </button>
          ))}
        </div>
      </div>
      {to && (
        <>
          <div>
            <label htmlFor="msg" className={label}>
              Mensaje para el ciudadano {required ? <span className="text-danger">(obligatorio)</span> : <span className="font-normal text-muted">(opcional)</span>}
            </label>
            <textarea id="msg" rows={3} maxLength={1000} className={field} value={message} onChange={(e) => setMessage(e.target.value)}
              placeholder={required ? "Explique la decisión en lenguaje claro. Lo verá en la app." : "Si lo deja vacío, verá un texto estándar."} />
          </div>
          <div>
            <label htmlFor="note" className={label}>Nota interna <span className="font-normal text-muted">(solo personal)</span></label>
            <textarea id="note" rows={2} maxLength={2000} className={field} value={note} onChange={(e) => setNote(e.target.value)} />
          </div>
          <button type="submit" className={btn.primary} disabled={a.busy || (required && message.trim().length < 5)}>
            {a.busy ? "Guardando…" : `Confirmar: ${STATUS_LABEL[to]}`}
          </button>
        </>
      )}
      <Feedback error={a.error} ok={a.ok} />
    </form>
  );
}

function AssignBox({ d, reload }: { d: Detail; reload: () => Promise<void> }) {
  const team = useApi<TeamMember[]>(d.permissions.can_assign ? "/staff/team" : null);
  const [staffId, setStaffId] = useState("");
  const a = useAction(reload);
  const closed = d.status === "CERRADO" || d.status === "NO_PROCEDE";
  return (
    <div className="space-y-3">
      <p className="text-sm">
        {d.assigned_name ? <>Asignado a <span className="font-semibold">{d.assigned_name}</span></> : <span className="text-muted">Sin asignar</span>}
      </p>
      {d.permissions.can_take && (
        <button className={btn.primary} disabled={a.busy}
          onClick={() => a.run(() => post(`/staff/incidents/${d.radicado}/take`), "Ahora el reporte está a su cargo.")}>
          Tomar este reporte
        </button>
      )}
      {d.permissions.can_assign && !closed && (
        <form className="flex gap-2" onSubmit={(e) => {
          e.preventDefault();
          if (staffId) void a.run(() => post(`/staff/incidents/${d.radicado}/assign`, { staff_id: staffId }), "Reporte asignado.");
        }}>
          <label htmlFor="staff" className="sr-only">Funcionario</label>
          <select id="staff" className={field} value={staffId} onChange={(e) => setStaffId(e.target.value)}>
            <option value="">Elegir funcionario…</option>
            {team.data?.map((m) => (
              <option key={m.id} value={m.id}>{m.full_name ?? m.id} · {m.role}</option>
            ))}
          </select>
          <button className={btn.secondary} disabled={!staffId || a.busy}>{d.assigned_to ? "Reasignar" : "Asignar"}</button>
        </form>
      )}
      <Feedback error={a.error} ok={a.ok} />
    </div>
  );
}

function PriorityBox({ d, reload }: { d: Detail; reload: () => Promise<void> }) {
  const a = useAction(reload);
  return (
    <div className="space-y-2">
      <label htmlFor="prio" className={label}>Prioridad</label>
      <select id="prio" className={field} value={d.priority} disabled={a.busy}
        onChange={(e) => a.run(() => post(`/staff/incidents/${d.radicado}/priority`, { priority: e.target.value }), "Prioridad actualizada.")}>
        {PRIORITIES.map((p) => <option key={p} value={p}>{PRIORITY_LABEL[p]}</option>)}
      </select>
      <Feedback error={a.error} ok={a.ok} />
    </div>
  );
}

function NoteForm({ d, reload }: { d: Detail; reload: () => Promise<void> }) {
  const [text, setText] = useState("");
  const [pub, setPub] = useState(false);
  const a = useAction(reload);
  return (
    <form className="space-y-2" onSubmit={async (e) => {
      e.preventDefault();
      if (await a.run(() => post(`/staff/incidents/${d.radicado}/notes`, { text, public: pub }),
        pub ? "Mensaje enviado al ciudadano." : "Nota interna guardada.")) setText("");
    }}>
      <div role="radiogroup" aria-label="Tipo de anotación" className="flex gap-1 rounded-lg bg-bg p-1 text-xs font-semibold">
        {[{ v: false, t: "Nota interna" }, { v: true, t: "Mensaje al ciudadano" }].map((o) => (
          <button key={o.t} type="button" role="radio" aria-checked={pub === o.v} onClick={() => setPub(o.v)}
            className={`flex-1 rounded-md px-3 py-1.5 ${pub === o.v ? "bg-surface text-navy-900 shadow-sm" : "text-muted"}`}>
            {o.t}
          </button>
        ))}
      </div>
      <label htmlFor="nota" className="sr-only">Texto</label>
      <textarea id="nota" rows={3} maxLength={2000} className={field} value={text} onChange={(e) => setText(e.target.value)}
        placeholder={pub ? "Lo verá el ciudadano en la app, en el seguimiento de su reporte." : "Solo la ve el personal."} />
      <button className={btn.secondary} disabled={a.busy || text.trim().length < 2}>{pub ? "Enviar mensaje" : "Guardar nota"}</button>
      <Feedback error={a.error} ok={a.ok} />
    </form>
  );
}

function Timeline({ items }: { items: Detail["history"] }) {
  return (
    <ol className="relative space-y-4 border-l border-line pl-5">
      {[...items].reverse().map((h, i) => (
        <li key={i} className="relative">
          <span aria-hidden className="absolute -left-[26px] top-1 size-3 rounded-full border-2 border-white"
            style={{ backgroundColor: h.internal ? "#94A3B8" : h.new_status ? STATUS_COLOR[h.new_status] : "#0B1F3A" }} />
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold text-navy-900">{ACTION_LABEL[h.action] ?? h.action}</span>
            {h.new_status && h.action !== "CREADO" && <StatusBadge status={h.new_status} />}
            <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold uppercase ${h.internal ? "bg-slate-200 text-slate-700" : "bg-signal/15 text-cyan-800"}`}>
              {h.internal ? "Interno" : "Visible al ciudadano"}
            </span>
          </div>
          {h.note && <p className="mt-1 whitespace-pre-line text-sm text-ink">{h.note}</p>}
          <p className="mt-0.5 text-xs text-muted">{h.actor} · {fmtDateTime(h.at)}</p>
        </li>
      ))}
    </ol>
  );
}

export function IncidentDetail({ radicado }: { radicado: string }) {
  const { data: d, error, loading, reload } = useApi<Detail>(`/staff/incidents/${encodeURIComponent(radicado)}`, 30_000);

  if (error && !d)
    return (
      <div className="space-y-4">
        <Link href="/incidentes" className="text-sm font-semibold text-navy-700 hover:underline">← Volver a la bandeja</Link>
        <ErrorBox message={error.status === 404 ? `No existe el reporte ${radicado}.` : error.message} onRetry={reload} />
      </div>
    );
  if (loading || !d) return <Skeleton className="h-[600px]" />;

  const canManage = d.permissions.can_manage;
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Link href="/incidentes" className="text-sm font-semibold text-navy-700 hover:underline">← Volver a la bandeja</Link>
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge status={d.status} />
          <PriorityBadge priority={d.priority} />
          {d.out_of_scope && <span className="rounded bg-alert/15 px-2 py-0.5 text-xs font-bold text-alert">Fuera del ámbito territorial</span>}
        </div>
      </div>

      <div className="grid gap-5 xl:grid-cols-[1fr_380px]">
        <div className="space-y-5">
          <Card title={`${d.category} · ${d.radicado}`}>
            <p className="whitespace-pre-line text-[15px] leading-relaxed text-ink">{d.description}</p>
            {d.additional_info && <p className="mt-3 whitespace-pre-line text-sm text-muted">{d.additional_info}</p>}
            <dl className="mt-4 divide-y divide-line border-t border-line">
              <Row k="Ocurrió">{fmtDateTime(d.occurred_at)}</Row>
              <Row k="Recibido">{fmtDateTime(d.received_at)} <span className="text-muted">({timeAgo(d.received_at)})</span></Row>
              {d.first_response_at && <Row k="Primera gestión">{fmtDateTime(d.first_response_at)}</Row>}
              {d.closed_at && <Row k="Cerrado">{fmtDateTime(d.closed_at)}</Row>}
              <Row k="Origen">{SOURCE_LABEL[d.source] ?? d.source}</Row>
              <Row k="Ubicación">
                {d.address_text && <span className="block">{d.address_text}</span>}
                <span className="font-mono text-xs">{d.lat.toFixed(5)}, {d.lon.toFixed(5)}</span>
                <span className="text-muted"> · {d.location_manual ? "marcada en el mapa" : `GPS ±${Math.round(d.accuracy_m ?? 0)} m`}</span>
              </Row>
            </dl>
          </Card>

          <Card title="Ubicación">
            <IncidentMap center={[d.lat, d.lon]} zoom={16} height={300}
              single={{ lat: d.lat, lon: d.lon, accuracy: d.location_manual ? null : d.accuracy_m, color: STATUS_COLOR[d.status] }} />
          </Card>

          <Card title={`Fotos (${d.evidence.length})`}>
            {d.evidence.length === 0 ? (
              <p className="text-sm text-muted">El ciudadano no adjuntó fotos.</p>
            ) : (
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {d.evidence.map((e) =>
                  e.url ? (
                    <a key={e.id} href={e.url} target="_blank" rel="noopener noreferrer" className="group block overflow-hidden rounded-lg border border-line">
                      {/* URL firmada de corta duración: no se usa next/image para no cachearla */}
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={e.url} alt={`Foto adjunta al reporte ${d.radicado}`} className="aspect-square w-full object-cover transition group-hover:scale-105"
                        onError={(ev) => {
                          const img = ev.currentTarget;
                          img.replaceWith(Object.assign(document.createElement("span"), {
                            className: "flex aspect-square items-center justify-center p-3 text-center text-xs text-slate-500",
                            textContent: "El archivo no es una imagen válida. Ábralo para descargarlo.",
                          }));
                        }} />
                    </a>
                  ) : (
                    <div key={e.id} className="flex aspect-square items-center justify-center rounded-lg border border-line text-xs text-muted">
                      Almacenamiento no disponible
                    </div>
                  ),
                )}
              </div>
            )}
          </Card>

          <Card title="Historial completo">
            <Timeline items={d.history} />
          </Card>
        </div>

        <div className="space-y-5">
          <Card title="Gestión">
            <div className="space-y-5">
              <AssignBox d={d} reload={reload} />
              {canManage ? (
                <>
                  <hr className="border-line" />
                  <StatusForm d={d} reload={reload} />
                  <hr className="border-line" />
                  <PriorityBox d={d} reload={reload} />
                </>
              ) : (
                <p className="rounded-lg bg-bg p-3 text-xs text-muted">
                  {d.permissions.can_take
                    ? "Tome el reporte para poder cambiar su estado, prioridad y escribir notas."
                    : "Solo el funcionario asignado o un supervisor pueden gestionar este reporte."}
                </p>
              )}
            </div>
          </Card>

          {canManage && (
            <Card title="Anotaciones">
              <NoteForm d={d} reload={reload} />
            </Card>
          )}

          <Card title="Reportante">
            {d.reporter.type === "ANONIMO" ? (
              <p className="text-sm text-muted">Reporte anónimo. El ciudadano consulta el avance con su radicado y código; no hay datos de contacto.</p>
            ) : (
              <dl className="divide-y divide-line">
                <Row k="Nombre">{d.reporter.full_name ?? "—"}</Row>
                <Row k="Correo">{d.reporter.email ? <a className="text-navy-700 underline" href={`mailto:${d.reporter.email}`}>{d.reporter.email}</a> : "—"}</Row>
                <Row k="Teléfono">{d.reporter.phone ? <a className="text-navy-700 underline" href={`tel:${d.reporter.phone}`}>{d.reporter.phone}</a> : "—"}</Row>
              </dl>
            )}
            <p className="mt-3 text-[11px] text-muted">Datos personales protegidos (Ley 1581 de 2012). Cada consulta queda en la auditoría.</p>
          </Card>
        </div>
      </div>
    </div>
  );
}
