// Verificación E2E: login real contra Supabase local y render del panel con cookie de sesión SSR.
import { createClient } from "@supabase/supabase-js";

const [, , email, password] = process.argv;
const anon = process.env.SUPABASE_ANON_KEY;
const sb = createClient("http://127.0.0.1:54321", anon, { auth: { persistSession: false } });
const { data, error } = await sb.auth.signInWithPassword({ email, password });
if (error) throw error;

const value = "base64-" + Buffer.from(JSON.stringify(data.session)).toString("base64url");
const name = "sb-127-auth-token";
const chunks = value.match(/.{1,3180}/g);
const cookie = chunks.length === 1 ? `${name}=${value}` : chunks.map((c, i) => `${name}.${i}=${c}`).join("; ");

const res = await fetch(`${process.env.WEB_URL ?? "http://localhost:4000"}/`, { headers: { cookie }, redirect: "manual" });
const html = await res.text();
console.log("status", res.status, res.headers.get("location") ?? "");
for (const needle of ["Estado de la plataforma", "Administrador Local", "Sin acceso al panel"]) {
  console.log(needle, "=>", html.includes(needle));
}
const me = await fetch(`${process.env.WEB_URL ?? "http://localhost:4000"}/api/py/me`, { headers: { Authorization: `Bearer ${data.session.access_token}` } });
console.log("/api/py/me via Next rewrite:", me.status, await me.text());
