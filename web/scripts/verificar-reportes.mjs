// Verificación E2E de la Fase 2 contra el stack LOCAL (Supabase + API FastAPI en :8000).
// Flujo: reporte anónimo → track → presign → PUT al almacenamiento S3 → confirm; ciudadano autenticado → reporte → /mine;
// el administrador recibe el INSERT por Realtime; una NOTA_INTERNA nunca aparece en el seguimiento.
// SOLO LOCAL: crea reportes rotulados "PRUEBA E2E" (el historial es inmutable; `supabase db reset` los limpia).
// Uso: node --env-file=.env.local scripts/verificar-reportes.mjs   (requiere admin.local@ y ciudadano.prueba@)
import { createClient } from "@supabase/supabase-js";

const SB = "http://127.0.0.1:54321";
const API = (process.env.API_URL ?? "http://127.0.0.1:8000") + "/api/py";
const anon = process.env.SUPABASE_ANON_KEY;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
let fallos = 0;
const check = (nombre, ok, extra = "") => {
  console.log(`${ok ? "OK   " : "FALLA"} ${nombre} ${extra}`);
  if (!ok) fallos++;
};

async function login(email, password) {
  const c = createClient(SB, anon, { auth: { persistSession: false } });
  const { data, error } = await c.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return { c, token: data.session.access_token, id: data.user.id };
}

async function api(path, { method = "GET", body, token, headers = {} } = {}) {
  const res = await fetch(API + path, {
    method,
    headers: { "Content-Type": "application/json", "X-Device-Id": "e2e-" + process.pid,
               ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null, text };
}

// ---------------------------------------------------------------- listener Realtime del administrador
const admin = await login("admin.local@example.com", "Admin-Local-2026");
admin.c.realtime.setAuth(admin.token);
const recibidos = [];
await new Promise((resolve, reject) => {
  admin.c.channel("e2e-reportes")
    .on("system", {}, (m) => (m.extension === "postgres_changes" && m.status === "ok" ? resolve() : null))
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "incidents" }, (p) => recibidos.push(p.new.radicado))
    .subscribe((s) => (s.endsWith("ERROR") || s === "TIMED_OUT" ? reject(new Error(s)) : null));
});

// ---------------------------------------------------------------- reporte anónimo
const cats = await api("/categories");
check("categorías públicas", cats.status === 200 && cats.json.length > 0, `(${cats.json?.length})`);
const reporte = {
  category_id: cats.json[0].id,
  description: "PRUEBA E2E — reporte anónimo desde script local",
  occurred_at: new Date(Date.now() - 3600_000).toISOString(),
  lat: 7.1193, lon: -73.1227, accuracy_m: 15, location_manual: false,
};
const a = await api("/reports/anonymous", { method: "POST", body: reporte });
check("reporte anónimo 201", a.status === 201, a.json?.radicado ?? a.text);
const { radicado, tracking_token, id } = a.json;

const t = await api("/reports/track", { method: "POST", body: { radicado, token: tracking_token } });
check("track con token", t.status === 200 && t.json.status === "RECIBIDO");
const malo = await api("/reports/track", { method: "POST", body: { radicado, token: "x".repeat(43) } });
const inexistente = await api("/reports/track", { method: "POST", body: { radicado: "BGA-2099-999999", token: tracking_token } });
check("token erróneo y radicado inexistente → mismo 404",
  malo.status === 404 && inexistente.status === 404 && malo.text === inexistente.text);

// ---------------------------------------------------------------- evidencia
const foto = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(2044, 7)]);
const p = await api("/evidence/presign", { method: "POST",
  body: { radicado, mime: "image/jpeg", size: foto.length, tracking_token } });
check("presign", p.status === 200, p.status !== 200 ? p.text : "");
const put = await fetch(p.json.upload_url, { method: "PUT", headers: p.json.headers, body: foto });
check("PUT al almacenamiento", put.ok, `(${put.status})`);
const cf = await api(`/evidence/${p.json.evidence_id}/confirm`, { method: "POST", body: { radicado, tracking_token } });
check("confirm → CONFIRMADA", cf.json?.status === "CONFIRMADA", cf.text);
const ajeno = await api("/evidence/presign", { method: "POST",
  body: { radicado, mime: "image/jpeg", size: 10, tracking_token: "otro" } });
check("presign con token ajeno → 404", ajeno.status === 404);

// ---------------------------------------------------------------- nota interna nunca visible
const svc = createClient(SB, service, { auth: { persistSession: false } });
const { error: eNota } = await svc.from("incident_history").insert({
  incident_id: id, action: "NOTA_INTERNA", note: "SECRETO-E2E nota interna", is_internal: true,
});
check("nota interna insertada", !eNota, eNota?.message ?? "");
const t2 = await api("/reports/track", { method: "POST", body: { radicado, token: tracking_token } });
check("track no expone la nota interna", t2.status === 200 && !t2.text.includes("SECRETO-E2E"));
check("track cuenta la evidencia", t2.json?.evidence_count === 1);

// ---------------------------------------------------------------- ciudadano autenticado
const cit = await login("ciudadano.prueba@example.com", "Clave-Segura-2026");
const b = await api("/reports", { method: "POST", token: cit.token,
  body: { ...reporte, description: "PRUEBA E2E — reporte autenticado desde script local" } });
check("reporte autenticado 201", b.status === 201, b.json?.radicado ?? b.text);
const mine = await api("/reports/mine", { token: cit.token });
check("/mine incluye el radicado", mine.json?.some((r) => r.radicado === b.json.radicado));
const det = await api(`/reports/${radicado}`, { token: cit.token });
check("el ciudadano no ve el anónimo ajeno → 404", det.status === 404);

// ---------------------------------------------------------------- Realtime
await new Promise((r) => setTimeout(r, 3000));
check("admin recibió ambos INSERT por Realtime",
  recibidos.includes(radicado) && recibidos.includes(b.json.radicado), JSON.stringify(recibidos));

console.log(fallos ? `\n${fallos} verificación(es) fallaron` : "\nTodas las verificaciones pasaron");
process.exit(fallos ? 1 : 0);
