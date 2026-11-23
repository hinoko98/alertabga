"use client";

import dynamic from "next/dynamic";
import { Skeleton } from "@/components/ui";

/** Leaflet usa `window`: se carga solo en el navegador. */
export const IncidentMap = dynamic(() => import("./LeafletMap"), {
  ssr: false,
  loading: () => <Skeleton className="h-[420px]" />,
});

export type { MapPoint } from "./LeafletMap";
