import { createBrowserClient } from "@supabase/ssr";

/** Cliente de navegador: usa solo la clave pública; RLS protege los datos. */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
