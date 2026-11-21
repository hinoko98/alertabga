import "server-only";
import { createClient } from "@/lib/supabase/server";
import { isStaffRole, type RoleCode, type StaffProfile } from "@/types/auth";

export type SessionState =
  | { kind: "anonymous" }
  | { kind: "forbidden"; email: string | null; role: RoleCode | null }
  | { kind: "staff"; profile: StaffProfile };

/** Resuelve la sesión en el servidor. El rol se lee de `profiles` (RLS), nunca de metadatos del cliente. */
export async function getSessionState(): Promise<SessionState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { kind: "anonymous" };

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, full_name, role_code, active")
    .eq("id", user.id)
    .maybeSingle();

  if (!profile || !profile.active || !isStaffRole(profile.role_code) || profile.role_code === "ciudadano") {
    return { kind: "forbidden", email: user.email ?? null, role: (profile?.role_code as RoleCode) ?? null };
  }
  return {
    kind: "staff",
    profile: { id: user.id, fullName: profile.full_name, email: user.email ?? null, role: profile.role_code },
  };
}
