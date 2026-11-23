"use client";

import { useState, type FormEvent } from "react";
import { useStaff } from "@/components/layout/SessionProvider";
import { btn, Card, Empty, ErrorBox, field, Kpi, label, Skeleton } from "@/components/ui";
import { ApiError, patch, post, put, useApi } from "@/lib/api";
import { fmtDateTime, fmtNumber } from "@/lib/incidents";
import { ROLE_LABEL, type RoleCode } from "@/types/auth";

interface User {
  id: string;
  email: string | null;
  full_name: string | null;
  role: RoleCode;
  active: boolean;
  last_sign_in_at: string | null;
}
interface CategoryAdmin {
  id: string;
  name: string;
  description: string;
  icon: string;
  color: string;
  severity_default: number;
  active: boolean;
}
interface AuditRow {
  at: string;
  action: string;
  entity: string;
  entity_id: string | null;
  actor: string;
  actor_role: string | null;
  metadata: Record<string, unknown>;
}

const STAFF_ROLE_OPTIONS: RoleCode[] = ["operador", "supervisor", "administrador"];

function useSubmit() {
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
      return true;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "No se pudo guardar.");
      return false;
    } finally {
      setBusy(false);
    }
  }
  return { busy, error, ok, run, setOk };
}

function Msg({ error, ok }: { error: string | null; ok: string | null }) {
  if (error) return <p role="alert" className="text-sm text-danger">{error}</p>;
  if (ok) return <p role="status" className="text-sm text-ok">{ok}</p>;
  return null;
}

// ------------------------------------------------------------------ personal
function Users() {
  const me = useStaff();
  const users = useApi<User[]>("/admin/users");
  const citizens = useApi<{ total: number; active: number; last_7_days: number }>("/admin/citizens");
  const s = useSubmit();
  const [created, setCreated] = useState<{ email: string; temporary_password: string | null } | null>(null);
  const [showAll, setShowAll] = useState(false);

  async function create(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const f = new FormData(form);
    let res: { email: string; temporary_password: string | null } | null = null;
    const done = await s.run(async () => {
      res = await post("/admin/users", {
        email: f.get("email"), full_name: f.get("full_name"), role: f.get("role"),
        password: (f.get("password") as string) || null,
      });
    }, "Cuenta creada.");
    if (done) {
      setCreated(res);
      form.reset();
      void users.reload();
    }
  }

  async function update(u: User, values: Partial<Pick<User, "role" | "active">>) {
    if (await s.run(() => patch(`/admin/users/${u.id}`, values), `Se actualizó ${u.email}.`)) void users.reload();
  }

  const list = (users.data ?? []).filter((u) => showAll || u.role !== "ciudadano");
  return (
    <div className="space-y-5">
      <div className="grid gap-4 sm:grid-cols-3">
        <Kpi label="Personal activo" value={(users.data ?? []).filter((u) => u.role !== "ciudadano" && u.active).length} />
        <Kpi label="Ciudadanos con cuenta (app)" value={citizens.data ? fmtNumber(citizens.data.total) : "—"}
          hint={citizens.data ? `${citizens.data.last_7_days} nuevos en 7 días` : undefined} />
        <Kpi label="Cuentas en Supabase" value={users.data?.length ?? "—"} hint="Personal y cuentas de prueba" />
      </div>

      <Card title="Crear cuenta del personal">
        <form onSubmit={create} className="grid gap-3 md:grid-cols-5">
          <div className="md:col-span-2">
            <label htmlFor="fn" className={label}>Nombre completo</label>
            <input id="fn" name="full_name" required minLength={3} maxLength={120} className={field} />
          </div>
          <div className="md:col-span-2">
            <label htmlFor="em" className={label}>Correo institucional</label>
            <input id="em" name="email" type="email" required className={field} />
          </div>
          <div>
            <label htmlFor="ro" className={label}>Rol</label>
            <select id="ro" name="role" className={field} defaultValue="operador">
              {STAFF_ROLE_OPTIONS.map((r) => <option key={r} value={r}>{ROLE_LABEL[r]}</option>)}
            </select>
          </div>
          <div className="md:col-span-2">
            <label htmlFor="pw" className={label}>Contraseña inicial <span className="font-normal text-muted">(opcional, 10+ caracteres)</span></label>
            <input id="pw" name="password" type="text" minLength={10} autoComplete="new-password" className={field}
              placeholder="Vacío = se genera una temporal" />
          </div>
          <div className="flex items-end md:col-span-3">
            <button className={btn.primary} disabled={s.busy}>{s.busy ? "Creando…" : "Crear cuenta"}</button>
          </div>
        </form>
        {created?.temporary_password && (
          <div className="mt-4 rounded-lg border border-alert/40 bg-alert/10 p-3 text-sm">
            Contraseña temporal para <b>{created.email}</b>: <code className="rounded bg-white px-1.5 py-0.5 font-mono">{created.temporary_password}</code>
            <p className="mt-1 text-xs text-muted">Se muestra una sola vez. Entréguela por un canal seguro.</p>
          </div>
        )}
      </Card>

      <Card title="Cuentas" action={
        <label className="flex items-center gap-2 text-xs text-muted">
          <input type="checkbox" checked={showAll} onChange={(e) => setShowAll(e.target.checked)} /> Incluir cuentas sin rol institucional
        </label>}>
        <Msg error={s.error} ok={s.ok} />
        {users.error && <ErrorBox message={users.error.message} onRetry={users.reload} />}
        {users.loading && <Skeleton className="h-40" />}
        {users.data && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-muted">
                <tr><th className="py-2">Nombre</th><th>Correo</th><th>Rol</th><th>Estado</th><th>Último ingreso</th></tr>
              </thead>
              <tbody className="divide-y divide-line">
                {list.map((u) => {
                  const self = u.id === me.id;
                  return (
                    <tr key={u.id} className={u.active ? "" : "opacity-60"}>
                      <td className="py-2.5 font-medium text-ink">{u.full_name ?? "—"} {self && <span className="text-xs text-muted">(usted)</span>}</td>
                      <td className="text-muted">{u.email}</td>
                      <td>
                        <select aria-label={`Rol de ${u.email}`} className={`${field} w-40 py-1`} value={u.role} disabled={self || s.busy}
                          onChange={(e) => update(u, { role: e.target.value as RoleCode })}>
                          {[...STAFF_ROLE_OPTIONS, "ciudadano" as RoleCode].map((r) => <option key={r} value={r}>{ROLE_LABEL[r]}</option>)}
                        </select>
                      </td>
                      <td>
                        <button className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${u.active ? "bg-ok/15 text-ok" : "bg-slate-200 text-slate-600"}`}
                          disabled={self || s.busy} onClick={() => update(u, { active: !u.active })}
                          title={self ? "No puede desactivar su propia cuenta" : u.active ? "Desactivar" : "Activar"}>
                          {u.active ? "Activa" : "Inactiva"}
                        </button>
                      </td>
                      <td className="text-xs text-muted">{fmtDateTime(u.last_sign_in_at)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

// ------------------------------------------------------------------ categorías
function Categories() {
  const cats = useApi<CategoryAdmin[]>("/admin/categories");
  const s = useSubmit();

  async function create(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const f = new FormData(form);
    const done = await s.run(() => post("/admin/categories", {
      name: f.get("name"), description: f.get("description"), color: f.get("color"),
      severity_default: Number(f.get("severity")),
    }), "Categoría creada. Ya aparece en la app.");
    if (done) {
      form.reset();
      void cats.reload();
    }
  }

  async function update(c: CategoryAdmin, values: Partial<CategoryAdmin>, msg: string) {
    if (await s.run(() => patch(`/admin/categories/${c.id}`, values), msg)) void cats.reload();
  }

  return (
    <div className="space-y-5">
      <Card title="Nueva categoría de reporte">
        <form onSubmit={create} className="grid gap-3 md:grid-cols-6">
          <div className="md:col-span-2">
            <label htmlFor="cn" className={label}>Nombre</label>
            <input id="cn" name="name" required minLength={2} maxLength={80} className={field} />
          </div>
          <div className="md:col-span-2">
            <label htmlFor="cd" className={label}>Descripción (la ve el ciudadano)</label>
            <input id="cd" name="description" maxLength={300} className={field} />
          </div>
          <div>
            <label htmlFor="cc" className={label}>Color</label>
            <input id="cc" name="color" type="color" defaultValue="#F59E0B" className="h-9 w-full rounded-lg border border-line" />
          </div>
          <div>
            <label htmlFor="cs" className={label}>Severidad</label>
            <select id="cs" name="severity" defaultValue="3" className={field}>
              {[1, 2, 3, 4, 5].map((n) => <option key={n}>{n}</option>)}
            </select>
          </div>
          <div className="md:col-span-6"><button className={btn.primary} disabled={s.busy}>Crear categoría</button></div>
        </form>
      </Card>
      <Card title="Categorías">
        <Msg error={s.error} ok={s.ok} />
        {cats.error && <ErrorBox message={cats.error.message} onRetry={cats.reload} />}
        {cats.loading && <Skeleton className="h-40" />}
        {cats.data && cats.data.length === 0 && <Empty>No hay categorías.</Empty>}
        <ul className="divide-y divide-line">
          {cats.data?.map((c) => (
            <li key={c.id} className="flex flex-wrap items-center gap-3 py-3">
              <span aria-hidden className="size-4 rounded" style={{ backgroundColor: c.color }} />
              <div className="min-w-48 flex-1">
                <p className="font-semibold text-ink">{c.name}</p>
                <p className="text-xs text-muted">{c.description || "Sin descripción"} · severidad {c.severity_default}</p>
              </div>
              <button className={c.active ? btn.secondary : btn.primary} disabled={s.busy}
                onClick={() => update(c, { active: !c.active }, c.active ? `«${c.name}» ya no aparece en la app.` : `«${c.name}» está activa.`)}>
                {c.active ? "Desactivar" : "Activar"}
              </button>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}

// ------------------------------------------------------------------ ajustes
function Settings() {
  const settings = useApi<Record<string, Record<string, unknown>>>("/admin/settings");
  const s = useSubmit();
  if (settings.error) return <ErrorBox message={settings.error.message} onRetry={settings.reload} />;
  if (!settings.data) return <Skeleton className="h-40" />;
  const rl = (settings.data.rate_limit_reports ?? { max: 5, window_minutes: 60 }) as { max: number; window_minutes: number };
  const scope = settings.data.territorial_scope as Record<string, number | string | boolean> | undefined;
  const ev = settings.data.evidence_limits as { max_files: number; max_bytes: number; mime: string[] } | undefined;

  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <Card title="Límite de reportes por ciudadano o dispositivo">
        <form className="space-y-3" onSubmit={async (e) => {
          e.preventDefault();
          const f = new FormData(e.currentTarget);
          if (await s.run(() => put("/admin/settings/rate-limit", { max: Number(f.get("max")), window_minutes: Number(f.get("win")) }),
            "Límite actualizado. Aplica de inmediato.")) void settings.reload();
        }}>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label htmlFor="max" className={label}>Reportes máximos</label>
              <input id="max" name="max" type="number" min={1} max={100} defaultValue={rl.max} className={field} />
            </div>
            <div>
              <label htmlFor="win" className={label}>En una ventana de (min)</label>
              <input id="win" name="win" type="number" min={5} max={1440} defaultValue={rl.window_minutes} className={field} />
            </div>
          </div>
          <p className="text-xs text-muted">Evita abuso sin bloquear a quien reporta de buena fe. Valor actual: {rl.max} cada {rl.window_minutes} min.</p>
          <button className={btn.primary} disabled={s.busy}>Guardar</button>
          <Msg error={s.error} ok={s.ok} />
        </form>
      </Card>
      <Card title="Ámbito territorial y evidencias (solo lectura)">
        <dl className="space-y-2 text-sm">
          {scope && (
            <div>
              <dt className="text-muted">Recuadro de Bucaramanga</dt>
              <dd className="font-mono text-xs">lat {String(scope.min_lat)} a {String(scope.max_lat)} · lon {String(scope.min_lon)} a {String(scope.max_lon)}</dd>
              <dd className="text-xs text-alert">{scope.official ? "Límite oficial" : "Provisional, hasta tener el límite oficial"}</dd>
            </div>
          )}
          {ev && (
            <div>
              <dt className="text-muted">Fotos por reporte</dt>
              <dd>Máx. {ev.max_files} · {(ev.max_bytes / 1048576).toFixed(0)} MB c/u · {ev.mime.map((m) => m.replace("image/", "")).join(", ")}</dd>
            </div>
          )}
        </dl>
      </Card>
    </div>
  );
}

// ------------------------------------------------------------------ auditoría
function Audit() {
  const [action, setAction] = useState("");
  const rows = useApi<AuditRow[]>(`/admin/audit?limit=200${action ? `&action=${action}` : ""}`);
  const ACTIONS = ["", "VER_INCIDENTE", "CAMBIO_ESTADO", "TOMAR_INCIDENTE", "ASIGNAR_INCIDENTE", "NOTA_INTERNA",
    "MENSAJE_CIUDADANO", "CAMBIO_PRIORIDAD", "EXPORTAR_INCIDENTES", "CREAR_USUARIO", "ACTUALIZAR_USUARIO",
    "CREAR_CATEGORIA", "ACTUALIZAR_CATEGORIA", "ACTUALIZAR_AJUSTE", "REPORTE_CREADO", "EVIDENCIA_SUBIDA"];
  return (
    <Card title="Registro de auditoría (solo inserción)" action={
      <select aria-label="Acción" className={`${field} w-56 py-1`} value={action} onChange={(e) => setAction(e.target.value)}>
        {ACTIONS.map((a) => <option key={a} value={a}>{a || "Todas las acciones"}</option>)}
      </select>}>
      {rows.error && <ErrorBox message={rows.error.message} onRetry={rows.reload} />}
      {rows.loading && <Skeleton className="h-60" />}
      {rows.data && rows.data.length === 0 && <Empty>Sin registros.</Empty>}
      {rows.data && rows.data.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-muted">
              <tr><th className="py-2">Fecha</th><th>Acción</th><th>Quién</th><th>Sobre</th><th>Detalle</th></tr>
            </thead>
            <tbody className="divide-y divide-line">
              {rows.data.map((r, i) => (
                <tr key={i}>
                  <td className="whitespace-nowrap py-2 text-xs text-muted">{fmtDateTime(r.at)}</td>
                  <td className="font-mono text-xs">{r.action}</td>
                  <td>{r.actor} <span className="text-xs text-muted">{r.actor_role}</span></td>
                  <td className="font-mono text-[11px] text-muted">{r.entity}{r.entity_id ? ` · ${r.entity_id.slice(0, 8)}` : ""}</td>
                  <td className="max-w-xs truncate font-mono text-[11px] text-muted">{Object.keys(r.metadata).length ? JSON.stringify(r.metadata) : ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

const TABS = [
  { id: "usuarios", label: "Personal", el: <Users /> },
  { id: "categorias", label: "Categorías", el: <Categories /> },
  { id: "ajustes", label: "Ajustes", el: <Settings /> },
  { id: "auditoria", label: "Auditoría", el: <Audit /> },
];

export function Administration() {
  const [tab, setTab] = useState("usuarios");
  return (
    <div className="space-y-5">
      <div role="tablist" aria-label="Administración" className="flex flex-wrap gap-1 rounded-xl border border-line bg-surface p-1">
        {TABS.map((t) => (
          <button key={t.id} role="tab" aria-selected={tab === t.id} onClick={() => setTab(t.id)}
            className={`rounded-lg px-4 py-1.5 text-sm font-semibold ${tab === t.id ? "bg-navy-900 text-white" : "text-navy-900 hover:bg-bg"}`}>
            {t.label}
          </button>
        ))}
      </div>
      {TABS.find((t) => t.id === tab)?.el}
    </div>
  );
}
