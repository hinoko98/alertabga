import { fmtNumber } from "@/lib/incidents";

/** Barras horizontales con etiqueta y valor (categorías, barrios, estados). Accesible: es una lista. */
export function BarList({ items, color = "#13305A", max }: {
  items: { key: string; count: number; color?: string }[];
  color?: string;
  max?: number;
}) {
  const top = max ?? Math.max(1, ...items.map((i) => i.count));
  if (items.length === 0) return <p className="py-6 text-center text-sm text-muted">Sin datos en este periodo.</p>;
  return (
    <ul className="space-y-2.5">
      {items.map((i) => (
        <li key={i.key}>
          <div className="mb-1 flex items-baseline justify-between gap-3 text-xs">
            <span className="truncate font-medium text-ink" title={i.key}>{i.key || "Sin categoría"}</span>
            <span className="font-mono tabular-nums text-muted">{fmtNumber(i.count)}</span>
          </div>
          <div className="h-2 rounded-full bg-slate-100">
            <div
              className="h-2 rounded-full"
              style={{ width: `${(i.count / top) * 100}%`, backgroundColor: i.color ?? color }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}

/** Columnas verticales en SVG (series por día, hora o día de la semana). */
export function ColumnChart({ data, height = 160, color = "#06B6D4", labelEvery = 1, ariaLabel }: {
  data: { label: string; value: number }[];
  height?: number;
  color?: string;
  labelEvery?: number;
  ariaLabel: string;
}) {
  const max = Math.max(1, ...data.map((d) => d.value));
  const w = 100 / Math.max(1, data.length);
  const total = data.reduce((s, d) => s + d.value, 0);
  return (
    <figure>
      <svg viewBox={`0 0 100 ${height}`} preserveAspectRatio="none" className="w-full" style={{ height }} role="img"
        aria-label={`${ariaLabel}: ${data.map((d) => `${d.label} ${d.value}`).join(", ")}`}>
        {[0.25, 0.5, 0.75].map((f) => (
          <line key={f} x1="0" x2="100" y1={height * f} y2={height * f} stroke="#EEF2F7" strokeWidth="0.3" vectorEffect="non-scaling-stroke" />
        ))}
        {data.map((d, i) => {
          const h = (d.value / max) * (height - 4);
          return (
            <rect key={i} x={i * w + w * 0.15} y={height - h} width={w * 0.7} height={Math.max(h, d.value ? 1 : 0)} rx="0.6" fill={color}>
              <title>{`${d.label}: ${d.value}`}</title>
            </rect>
          );
        })}
      </svg>
      <div className="mt-1.5 flex text-[10px] text-muted">
        {data.map((d, i) => (
          <span key={i} className="flex-1 truncate text-center">{i % labelEvery === 0 ? d.label : ""}</span>
        ))}
      </div>
      <figcaption className="sr-only">Total {total}</figcaption>
    </figure>
  );
}

/** Anillo de proporciones (estados). */
export function Donut({ items, size = 140 }: { items: { key: string; label: string; count: number; color: string }[]; size?: number }) {
  const total = items.reduce((s, i) => s + i.count, 0);
  const r = 15.9155; // circunferencia 100
  let offset = 25;
  return (
    <div className="flex items-center gap-5">
      <svg viewBox="0 0 42 42" width={size} height={size} role="img" aria-label={items.map((i) => `${i.label} ${i.count}`).join(", ")}>
        <circle cx="21" cy="21" r={r} fill="none" stroke="#EEF2F7" strokeWidth="5" />
        {total > 0 &&
          items.filter((i) => i.count > 0).map((i) => {
            const pct = (i.count / total) * 100;
            const el = (
              <circle key={i.key} cx="21" cy="21" r={r} fill="none" stroke={i.color} strokeWidth="5"
                strokeDasharray={`${pct} ${100 - pct}`} strokeDashoffset={offset} />
            );
            offset -= pct;
            return el;
          })}
        <text x="21" y="20.5" textAnchor="middle" className="fill-navy-900" style={{ fontSize: 7, fontWeight: 700 }}>{total}</text>
        <text x="21" y="26" textAnchor="middle" className="fill-slate-500" style={{ fontSize: 3 }}>abiertos</text>
      </svg>
      <ul className="space-y-1.5 text-xs">
        {items.map((i) => (
          <li key={i.key} className="flex items-center gap-2">
            <span aria-hidden className="size-2.5 rounded-sm" style={{ backgroundColor: i.color }} />
            <span className="text-ink">{i.label}</span>
            <span className="font-mono tabular-nums text-muted">{i.count}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
