import type { Metadata } from "next";
import { Administration } from "@/components/admin/Administration";
import { Forbidden } from "@/components/ui";
import { getSessionState } from "@/services/session";

export const metadata: Metadata = { title: "Administración" };

export default async function AdminPage() {
  const session = await getSessionState();
  if (session.kind !== "staff" || session.profile.role !== "administrador") {
    return <Forbidden>La administración está disponible solo para administradores.</Forbidden>;
  }
  return <Administration />;
}
