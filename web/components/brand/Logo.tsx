type LogoProps = { size?: number; withWordmark?: boolean; tone?: "light" | "dark" };

/** Escudo con mapa y pin de ubicación (propuesta 1 de identidad AlertaBGA). */
export function LogoMark({ size = 36 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" role="img" aria-label="AlertaBGA">
      <path d="M24 3 6 9.5v13.2C6 34.3 13.7 42.6 24 45c10.3-2.4 18-10.7 18-22.3V9.5L24 3Z" fill="#0B1F3A" />
      <path d="M24 6.4 9 11.8v10.9c0 9.8 6.4 16.9 15 19 8.6-2.1 15-9.2 15-19V11.8L24 6.4Z" fill="#13305A" />
      {/* retícula de mapa */}
      <path d="M11 20.5h26M11 28h26M19 12v28M29 12v28" stroke="#06B6D4" strokeOpacity=".35" strokeWidth="1" />
      {/* pin */}
      <path d="M24 13.5c-4.1 0-7.3 3.2-7.3 7.2 0 5.3 7.3 13 7.3 13s7.3-7.7 7.3-13c0-4-3.2-7.2-7.3-7.2Z" fill="#06B6D4" />
      <circle cx="24" cy="20.7" r="2.8" fill="#F59E0B" />
    </svg>
  );
}

export function Logo({ size = 36, withWordmark = true, tone = "light" }: LogoProps) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <LogoMark size={size} />
      {withWordmark && (
        <span className={`text-lg font-bold tracking-tight ${tone === "light" ? "text-white" : "text-navy-900"}`}>
          Alerta<span className="text-signal">BGA</span>
        </span>
      )}
    </span>
  );
}
