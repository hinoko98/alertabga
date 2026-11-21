"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Check = { label: string; detail: string; state: "ok" | "warn" | "error" | "pending" };

const STATE_STYLE: Record<Check["state"], { dot: string; text: string }> = {
  ok: { dot: "bg-ok", text: "Operativo" },
  warn: { dot: "bg-alert", text: "Pendiente de configurar" },
  error: { dot: "bg-danger", text: "Con fallas" },
  pending: { dot: "bg-slate-300 animate-pulse", text: "Verificando" },
};

function StatusCard({ check }: { check: Check }) {
  const s = STATE_STYLE[check.state];
  return (
    <li className="rounded-xl border border-line bg-surface p-5">
      <div className="flex items-center justify-between gap-3">
        <h3 className="font-semibold text-navy-900">{check.label}</h3>
        <span className="inline-flex items-center gap-2 text-xs font-medium text-ink">
          <span aria-hidden className={`size-2.5 rounded-full ${s.dot}`} />
          {s.text}
        </span>
      </div>
      <p className="mt-2 font-mono text-xs text-muted">{check.detail}</p>
    </li>
  );
}

export function SystemStatus() {
  const [api, setApi] = useState<Check>({ label: "API Python (FastAPI)", detail: "—", state: "pending" });
  const [auth, setAuth] = useState<Check>({ label: "Autenticación y rol (JWT → API)", detail: "—", state: "pending" });
  const [deps, setDeps] = useState<Check[]>([
    { label: "Supabase (Postgres + Auth)", detail: "—", state: "pending" },
    { label: "Cloudflare R2 (evidencias)", detail: "—", state: "pending" },
    { label: "MongoDB (histórico)", detail: "—", state: "pending" },
  ]);
  const [rt, setRt] = useState<Check>({ label: "Supabase Realtime", detail: "—", state: "pending" });
  const [events, setEvents] = useState<{ at: string; type: string }[]>([]);

  useEffect(() => {
    const supabase = createClient();

    fetch("/api/py/health/deps")
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((d: { supabase: string; r2: string; mongodb: string; time: string }) => {
        setApi({ label: "API Python (FastAPI)", detail: `respuesta ${d.time}`, state: "ok" });
        setDeps([
          { label: "Supabase (Postgres + Auth)", detail: d.supabase, state: d.supabase === "ok" ? "ok" : "error" },
          { label: "Cloudflare R2 (evidencias)", detail: d.r2, state: d.r2 === "configurado" ? "ok" : "warn" },
          {
            label: "MongoDB (histórico)",
            detail: d.mongodb,
            state: d.mongodb === "ok" ? "ok" : d.mongodb === "no_configurado" ? "warn" : "error",
          },
        ]);
      })
      .catch((e: Error) => setApi({ label: "API Python (FastAPI)", detail: e.message, state: "error" }));

    supabase.auth.getSession().then(async ({ data }) => {
      const token = data.session?.access_token;
      if (!token) return setAuth((c) => ({ ...c, detail: "sin sesión", state: "error" }));
      const r = await fetch("/api/py/me", { headers: { Authorization: `Bearer ${token}` } });
      if (!r.ok) return setAuth((c) => ({ ...c, detail: `HTTP ${r.status}`, state: "error" }));
      const me = (await r.json()) as { role: string };
      setAuth((c) => ({ ...c, detail: `token válido · rol ${me.role}`, state: "ok" }));
    });

    // Eventos reales de la tabla incidents, filtrados por RLS según el rol del usuario.
    // Se considera operativo solo cuando el servidor confirma la suscripción a Postgres (no basta SUBSCRIBED).
    const channel = supabase
      .channel("estado-incidentes")
      .on("system", {}, (msg: { extension?: string; status?: string; message?: string }) => {
        if (msg.extension !== "postgres_changes") return;
        setRt((c) => ({
          ...c,
          detail: msg.message ?? "",
          state: msg.status === "ok" ? "ok" : "error",
        }));
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "incidents" }, (payload) => {
        setEvents((prev) => [{ at: new Date().toLocaleTimeString("es-CO"), type: payload.eventType }, ...prev].slice(0, 5));
      })
      .subscribe((status) => {
        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          setRt((c) => ({ ...c, detail: `canal ${status.toLowerCase()}`, state: "error" }));
        }
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  return (
    <div className="space-y-8">
      <section aria-labelledby="conexiones" className="space-y-4">
        <div>
          <h2 id="conexiones" className="text-base font-bold text-navy-900">Conexiones entre componentes</h2>
          <p className="text-sm text-muted">Verificación en vivo: navegador → Next.js → FastAPI → Supabase / R2 / MongoDB.</p>
        </div>
        <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {[api, auth, ...deps, rt].map((c) => (
            <StatusCard key={c.label} check={c} />
          ))}
        </ul>
      </section>

      <section aria-labelledby="eventos" className="rounded-xl border border-line bg-surface p-5">
        <h2 id="eventos" className="font-semibold text-navy-900">Eventos de incidentes recibidos en tiempo real</h2>
        {events.length === 0 ? (
          <p className="mt-2 text-sm text-muted">
            Aún no hay eventos en esta sesión. Cuando se cree o actualice un incidente de su ámbito, aparecerá aquí.
          </p>
        ) : (
          <ul className="mt-3 space-y-1 font-mono text-xs">
            {events.map((e, i) => (
              <li key={i}>
                {e.at} · {e.type}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
