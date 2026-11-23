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
    { label: "Supabase (personal y configuración)", detail: "—", state: "pending" },
    { label: "Almacenamiento de evidencias", detail: "—", state: "pending" },
    { label: "MongoDB (reportes e histórico)", detail: "—", state: "pending" },
  ]);

  useEffect(() => {
    const supabase = createClient();

    fetch("/api/py/health/deps")
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((d: { supabase: string; r2: string; mongodb: string; time: string }) => {
        setApi({ label: "API Python (FastAPI)", detail: `respuesta ${d.time}`, state: "ok" });
        setDeps([
          { label: "Supabase (personal y configuración)", detail: d.supabase, state: d.supabase === "ok" ? "ok" : "error" },
          { label: "Almacenamiento de evidencias", detail: d.r2, state: d.r2 === "configurado" ? "ok" : "warn" },
          {
            label: "MongoDB (reportes e histórico)",
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

  }, []);

  return (
    <div className="space-y-8">
      <section aria-labelledby="conexiones" className="space-y-4">
        <div>
          <h2 id="conexiones" className="text-base font-bold text-navy-900">Conexiones entre componentes</h2>
          <p className="text-sm text-muted">Verificación en vivo: navegador → Next.js → FastAPI → Supabase / almacenamiento / MongoDB.</p>
        </div>
        <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {[api, auth, ...deps].map((c) => (
            <StatusCard key={c.label} check={c} />
          ))}
        </ul>
      </section>

    </div>
  );
}
