// Verifica Supabase Realtime + RLS: el administrador recibe el INSERT; un ciudadano ajeno NO.
// SOLO PARA ENTORNO LOCAL: crea un incidente rotulado "PRUEBA E2E" (el historial es inmutable; `supabase db reset` lo limpia).
// Uso: node --env-file=.env.local scripts/verificar-realtime.mjs  (requiere usuarios admin.local@ y ciudadano.prueba@ locales)
import { createClient } from "@supabase/supabase-js";

const anon = process.env.SUPABASE_ANON_KEY;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const URL = "http://127.0.0.1:54321";

async function listener(email, password) {
  const c = createClient(URL, anon, { auth: { persistSession: false } });
  const { data, error } = await c.auth.signInWithPassword({ email, password });
  if (error) throw error;
  c.realtime.setAuth(data.session.access_token);
  const got = [];
  await new Promise((resolve, reject) => {
    c.channel(`t-${email}`)
      .on("system", {}, (m) => (m.extension === "postgres_changes" && m.status === "ok" ? resolve() : null))
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "incidents" }, (p) => got.push(p.new.radicado))
      .subscribe((s) => (s.endsWith("ERROR") || s === "TIMED_OUT" ? reject(new Error(s)) : null));
  });
  return { c, got };
}

const admin = await listener("admin.local@example.com", "Admin-Local-2026");
const citizen = await listener("ciudadano.prueba@example.com", "Clave-Segura-2026");

const svc = createClient(URL, service, { auth: { persistSession: false } });
const { data: cat } = await svc.from("categories").select("id").eq("name", "Hurto").single();
const t0 = Date.now();
const { data: inc, error } = await svc.from("incidents").insert({
  radicado: "x", category_id: cat.id, description: "PRUEBA E2E REALTIME — entorno local de desarrollo",
  occurred_at: new Date().toISOString(), location: "SRID=4326;POINT(-73.12 7.12)",
  source: "APP_ANONIMO", anon_token_hash: "e2e",
}).select("radicado").single();
if (error) throw error;

await new Promise((r) => setTimeout(r, 4000));
console.log("insertado", inc.radicado);
console.log("admin recibió:", admin.got, admin.got.length ? `(< ${Date.now() - t0} ms ventana)` : "");
console.log("ciudadano ajeno recibió:", citizen.got);
process.exit(admin.got.includes(inc.radicado) && citizen.got.length === 0 ? 0 : 1);
