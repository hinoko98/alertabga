import Link from "next/link";
import type { ReactNode } from "react";
import { PRIORITY_COLOR, PRIORITY_LABEL, STATUS_COLOR, STATUS_LABEL, type Priority, type Status } from "@/lib/incidents";

export function Card({ title, action, children, className = "" }: {
  title?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`rounded-xl border border-line bg-surface p-5 ${className}`}>
      {(title || action) && (
        <div className="mb-4 flex items-center justify-between gap-3">
          {title && <h2 className="text-sm font-bold text-navy-900">{title}</h2>}
          {action}
        </div>
      )}
      {children}
    </section>
  );
}

export function Kpi({ label, value, hint, tone = "default", href }: {
  label: string;
  value: ReactNode;
  hint?: string;
  tone?: "default" | "alert" | "danger" | "ok";
  href?: string;
}) {
  const accent = { default: "bg-navy-700", alert: "bg-alert", danger: "bg-danger", ok: "bg-ok" }[tone];
  const body = (
    <div className="relative overflow-hidden rounded-xl border border-line bg-surface p-5 transition hover:border-navy-700/40">
      <span aria-hidden className={`absolute inset-y-0 left-0 w-1 ${accent}`} />
      <p className="text-xs font-semibold uppercase tracking-wide text-muted">{label}</p>
      <p className="mt-2 text-3xl font-bold tabular-nums text-navy-900">{value}</p>
      {hint && <p className="mt-1 text-xs text-muted">{hint}</p>}
    </div>
  );
  return href ? <Link href={href}>{body}</Link> : body;
}

function Chip({ color, children }: { color: string; children: ReactNode }) {
  return (
    <span
      className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold"
      style={{ backgroundColor: `${color}1A`, color }}
    >
      <span aria-hidden className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
      {children}
    </span>
  );
}

export const StatusBadge = ({ status }: { status: Status }) => (
  <Chip color={STATUS_COLOR[status]}>{STATUS_LABEL[status]}</Chip>
);

export const PriorityBadge = ({ priority }: { priority: Priority }) => (
  <Chip color={PRIORITY_COLOR[priority]}>{PRIORITY_LABEL[priority]}</Chip>
);

export function Skeleton({ className = "h-24" }: { className?: string }) {
  return <div aria-hidden className={`animate-pulse rounded-xl bg-slate-200/70 ${className}`} />;
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div role="alert" className="flex items-center justify-between gap-4 rounded-xl border border-danger/30 bg-danger/5 p-4 text-sm text-danger">
      <span>{message}</span>
      {onRetry && (
        <button onClick={onRetry} className="rounded-md border border-danger/40 px-3 py-1 font-medium hover:bg-danger/10">
          Reintentar
        </button>
      )}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="py-8 text-center text-sm text-muted">{children}</p>;
}

export const btn = {
  primary:
    "inline-flex items-center justify-center gap-2 rounded-lg bg-navy-900 px-4 py-2 text-sm font-semibold text-white transition hover:bg-navy-800 disabled:cursor-not-allowed disabled:opacity-50",
  secondary:
    "inline-flex items-center justify-center gap-2 rounded-lg border border-line bg-surface px-4 py-2 text-sm font-semibold text-navy-900 transition hover:bg-bg disabled:cursor-not-allowed disabled:opacity-50",
  danger:
    "inline-flex items-center justify-center gap-2 rounded-lg bg-danger px-4 py-2 text-sm font-semibold text-white transition hover:bg-danger/90 disabled:opacity-50",
};

export const field =
  "w-full rounded-lg border border-line bg-white px-3 py-2 text-sm text-ink outline-none transition focus:border-signal focus:ring-2 focus:ring-signal/25";

export const label = "mb-1 block text-xs font-semibold text-navy-900";

export function Forbidden({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto max-w-lg rounded-xl border border-line bg-surface p-8 text-center">
      <h2 className="text-lg font-bold text-navy-900">Sección restringida</h2>
      <p className="mt-2 text-sm text-muted">{children}</p>
    </div>
  );
}
