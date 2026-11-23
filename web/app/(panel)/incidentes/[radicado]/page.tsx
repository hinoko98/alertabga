import type { Metadata } from "next";
import { IncidentDetail } from "@/components/incidents/IncidentDetail";

type Props = { params: Promise<{ radicado: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { radicado } = await params;
  return { title: `Reporte ${decodeURIComponent(radicado)}` };
}

export default async function IncidentPage({ params }: Props) {
  const { radicado } = await params;
  return <IncidentDetail radicado={decodeURIComponent(radicado)} />;
}
