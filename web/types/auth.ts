export type RoleCode = "ciudadano" | "operador" | "supervisor" | "administrador";

export const STAFF_ROLES: readonly RoleCode[] = ["operador", "supervisor", "administrador"];

export const ROLE_LABEL: Record<RoleCode, string> = {
  ciudadano: "Ciudadano",
  operador: "Operador",
  supervisor: "Supervisor",
  administrador: "Administrador",
};

export interface StaffProfile {
  id: string;
  fullName: string | null;
  email: string | null;
  role: RoleCode;
}

export function isStaffRole(role: string | null | undefined): role is RoleCode {
  return !!role && (STAFF_ROLES as readonly string[]).includes(role);
}
