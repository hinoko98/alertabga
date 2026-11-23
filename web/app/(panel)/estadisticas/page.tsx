import type { Metadata } from "next";
import { Statistics } from "@/components/stats/Statistics";
import { Forbidden } from "@/components/ui";
import { getSessionState } from "@/services/session";

export const metadata: Metadata = { title: "Estadísticas" };

export default async function StatisticsPage() {
  const session = await getSessionState();
  if (session.kind !== "staff" || !["supervisor", "administrador"].includes(session.profile.role)) {
    return <Forbidden>Las estadísticas están disponibles para supervisores y administradores.</Forbidden>;
  }
  return <Statistics />;
}
