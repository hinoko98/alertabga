import type { Metadata } from "next";
import { Suspense } from "react";
import { Inbox } from "@/components/incidents/Inbox";
import { Skeleton } from "@/components/ui";

export const metadata: Metadata = { title: "Bandeja de incidentes" };

export default function IncidentsPage() {
  return (
    <Suspense fallback={<Skeleton className="h-96" />}>
      <Inbox />
    </Suspense>
  );
}
