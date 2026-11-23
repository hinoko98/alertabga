"use client";

import "leaflet/dist/leaflet.css";
import L from "leaflet";
import "leaflet.heat";
import Link from "next/link";
import { useEffect, useMemo } from "react";
import { Circle, CircleMarker, MapContainer, Popup, TileLayer, useMap } from "react-leaflet";
import { STATUS_COLOR, STATUS_LABEL, fmtDateTime, type Status } from "@/lib/incidents";

export const BUCARAMANGA: [number, number] = [7.1193, -73.1227];
const HISTORIC_GRADIENT = { 0.2: "#1D4278", 0.45: "#7C3AED", 0.7: "#DB2777", 1: "#F59E0B" };

export interface MapPoint {
  radicado: string;
  lat: number;
  lon: number;
  status: Status;
  category: string;
  priority: string;
  received_at: string;
  assigned_name: string | null;
}

/** Capa de calor (leaflet.heat). `points`: [lat, lon, intensidad]. */
function HeatLayer({ points, max, gradient }: {
  points: [number, number, number][];
  max: number;
  gradient?: Record<number, string>;
}) {
  const map = useMap();
  useEffect(() => {
    if (points.length === 0) return;
    const layer = L.heatLayer(points, { radius: 18, blur: 16, maxZoom: 16, max: Math.max(1, max), minOpacity: 0.25, gradient });
    layer.addTo(map);
    return () => {
      layer.remove();
    };
  }, [map, points, max, gradient]);
  return null;
}

function FitTo({ center, zoom }: { center: [number, number]; zoom: number }) {
  const map = useMap();
  useEffect(() => {
    map.setView(center, zoom);
  }, [map, center, zoom]);
  return null;
}

export default function LeafletMap({
  center = BUCARAMANGA,
  zoom = 13,
  height = 520,
  points = [],
  showMarkers = true,
  heat,
  historicHeat,
  single,
}: {
  center?: [number, number];
  zoom?: number;
  height?: number | string;
  points?: MapPoint[];
  showMarkers?: boolean;
  heat?: boolean;
  historicHeat?: { points: [number, number, number][]; max: number } | null;
  single?: { lat: number; lon: number; accuracy?: number | null; color: string };
}) {
  const heatPoints = useMemo<[number, number, number][]>(() => (heat ? points.map((p) => [p.lat, p.lon, 1]) : []), [heat, points]);
  return (
    <MapContainer center={center} zoom={zoom} scrollWheelZoom style={{ height, width: "100%" }}
      className="z-0 rounded-xl" attributionControl>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitTo center={center} zoom={zoom} />
      {historicHeat && historicHeat.points.length > 0 && (
        <HeatLayer points={historicHeat.points} max={historicHeat.max * 0.35}
          gradient={HISTORIC_GRADIENT} />
      )}
      {heat && heatPoints.length > 0 && <HeatLayer points={heatPoints} max={3} />}
      {showMarkers &&
        points.map((p) => (
          <CircleMarker key={p.radicado} center={[p.lat, p.lon]} radius={7}
            pathOptions={{ color: "#fff", weight: 1.5, fillColor: STATUS_COLOR[p.status], fillOpacity: 0.9 }}>
            <Popup>
              <div className="space-y-1 text-xs">
                <p className="font-mono font-bold">{p.radicado}</p>
                <p>{p.category} · {STATUS_LABEL[p.status]}</p>
                <p className="text-slate-500">{fmtDateTime(p.received_at)}</p>
                {p.assigned_name && <p>Asignado a {p.assigned_name}</p>}
                <Link href={`/incidentes/${p.radicado}`} className="font-semibold text-blue-700 underline">Abrir reporte</Link>
              </div>
            </Popup>
          </CircleMarker>
        ))}
      {single && (
        <>
          {single.accuracy ? (
            <Circle center={[single.lat, single.lon]} radius={single.accuracy}
              pathOptions={{ color: single.color, weight: 1, fillOpacity: 0.1 }} />
          ) : null}
          <CircleMarker center={[single.lat, single.lon]} radius={9}
            pathOptions={{ color: "#fff", weight: 2, fillColor: single.color, fillOpacity: 1 }} />
        </>
      )}
    </MapContainer>
  );
}
