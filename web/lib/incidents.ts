/** Tipos y etiquetas de incidentes compartidos por el panel. */

export const STATUSES = ["RECIBIDO", "EN_REVISION", "ASIGNADO", "EN_ATENCION", "CERRADO", "NO_PROCEDE"] as const;
export type Status = (typeof STATUSES)[number];
export const OPEN_STATUSES: Status[] = ["RECIBIDO", "EN_REVISION", "ASIGNADO", "EN_ATENCION"];

export const STATUS_LABEL: Record<Status, string> = {
  RECIBIDO: "Recibido",
  EN_REVISION: "En revisión",
  ASIGNADO: "Asignado",
  EN_ATENCION: "En atención",
  CERRADO: "Cerrado",
  NO_PROCEDE: "No procede",
};

export const STATUS_COLOR: Record<Status, string> = {
  RECIBIDO: "#2563EB",
  EN_REVISION: "#D97706",
  ASIGNADO: "#7C3AED",
  EN_ATENCION: "#0891B2",
  CERRADO: "#059669",
  NO_PROCEDE: "#64748B",
};

export const PRIORITIES = ["BAJA", "MEDIA", "ALTA", "CRITICA"] as const;
export type Priority = (typeof PRIORITIES)[number];
export const PRIORITY_LABEL: Record<Priority, string> = {
  BAJA: "Baja",
  MEDIA: "Media",
  ALTA: "Alta",
  CRITICA: "Crítica",
};
export const PRIORITY_COLOR: Record<Priority, string> = {
  BAJA: "#64748B",
  MEDIA: "#2563EB",
  ALTA: "#D97706",
  CRITICA: "#DC2626",
};

export const SOURCE_LABEL: Record<string, string> = {
  APP_ANONIMO: "App · anónimo",
  APP_AUTENTICADO: "App · con cuenta",
};

export interface IncidentRow {
  radicado: string;
  category: string;
  category_id: string | null;
  status: Status;
  priority: Priority;
  source: string;
  received_at: string;
  occurred_at: string | null;
  address_text: string | null;
  lat: number;
  lon: number;
  assigned_to: string | null;
  assigned_name: string | null;
  out_of_scope: boolean;
}

export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
}

export interface HistoryEntry {
  at: string;
  action: string;
  old_status: Status | null;
  new_status: Status | null;
  note: string | null;
  internal: boolean;
  actor: string;
}

export interface IncidentDetail extends IncidentRow {
  id: string;
  description: string;
  additional_info: string | null;
  accuracy_m: number | null;
  location_manual: boolean;
  verification_level: string | null;
  first_response_at: string | null;
  closed_at: string | null;
  reporter:
    | { type: "ANONIMO" }
    | { type: "CUENTA"; full_name: string | null; email: string | null; phone: string | null };
  evidence: { id: string; mime_type: string; size_bytes: number; url: string | null }[];
  history: HistoryEntry[];
  permissions: { transitions: Status[]; can_take: boolean; can_assign: boolean; can_manage: boolean };
}

export interface Category {
  id: string;
  name: string;
}

export interface TeamMember {
  id: string;
  full_name: string | null;
  role: string;
}

export const ACTION_LABEL: Record<string, string> = {
  CREADO: "Reporte recibido",
  CAMBIO_ESTADO: "Cambio de estado",
  CIERRE: "Cierre",
  ASIGNACION: "Asignación",
  NOTA_INTERNA: "Nota interna",
  MENSAJE_CIUDADANO: "Mensaje al ciudadano",
  CAMBIO_PRIORIDAD: "Prioridad",
};

const DATE_TIME = new Intl.DateTimeFormat("es-CO", {
  timeZone: "America/Bogota",
  day: "2-digit",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});
const DATE_SHORT = new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short" });

export const fmtDateTime = (iso: string | null | undefined) => (iso ? DATE_TIME.format(new Date(iso)) : "—");
export const fmtDay = (isoDate: string) => DATE_SHORT.format(new Date(`${isoDate}T12:00:00-05:00`)).replace(" de ", " ").replace(".", "");

/** "hace 5 min", "hace 3 h", "hace 2 d". */
export function timeAgo(iso: string): string {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (min < 1) return "ahora";
  if (min < 60) return `hace ${min} min`;
  const h = Math.round(min / 60);
  if (h < 48) return `hace ${h} h`;
  return `hace ${Math.round(h / 24)} d`;
}

export const fmtNumber = (n: number) => new Intl.NumberFormat("es-CO").format(n);
