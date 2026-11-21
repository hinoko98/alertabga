import type { Metadata } from "next";
import { SystemStatus } from "@/components/system/SystemStatus";

export const metadata: Metadata = { title: "Estado de la plataforma" };

export default function SystemStatusPage() {
  return <SystemStatus />;
}
