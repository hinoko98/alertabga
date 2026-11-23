import type { Metadata } from "next";
import { TerritorialMap } from "@/components/map/TerritorialMap";

export const metadata: Metadata = { title: "Mapa territorial" };

export default function MapPage() {
  return <TerritorialMap />;
}
