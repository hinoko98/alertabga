"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { StaffProfile } from "@/types/auth";

const SessionContext = createContext<StaffProfile | null>(null);

export function SessionProvider({ profile, children }: { profile: StaffProfile; children: ReactNode }) {
  return <SessionContext.Provider value={profile}>{children}</SessionContext.Provider>;
}

/** Perfil del funcionario (resuelto en el servidor desde `profiles`, no desde el cliente). */
export function useStaff(): StaffProfile {
  const p = useContext(SessionContext);
  if (!p) throw new Error("useStaff fuera de SessionProvider");
  return p;
}

export const isManager = (role: string) => role === "supervisor" || role === "administrador";
