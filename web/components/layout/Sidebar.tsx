import Link from "next/link";
import { Logo } from "@/components/brand/Logo";
import type { RoleCode } from "@/types/auth";

type NavItem = { href: string; label: string; roles: readonly RoleCode[]; ready: boolean };

// Las secciones se habilitan por fase; `ready: false` se muestra deshabilitado, sin enlaces muertos.
const NAV: NavItem[] = [
  { href: "/", label: "Estado de la plataforma", roles: ["operador", "supervisor", "administrador"], ready: true },
  { href: "/panel", label: "Panel principal", roles: ["operador", "supervisor", "administrador"], ready: false },
  { href: "/mapa", label: "Mapa territorial", roles: ["operador", "supervisor", "administrador"], ready: false },
  { href: "/incidentes", label: "Bandeja de incidentes", roles: ["operador", "supervisor", "administrador"], ready: false },
  { href: "/estadisticas", label: "Estadísticas", roles: ["supervisor", "administrador"], ready: false },
  { href: "/administracion", label: "Administración", roles: ["administrador"], ready: false },
];

export function Sidebar({ role }: { role: RoleCode }) {
  return (
    <aside className="hidden w-64 shrink-0 flex-col bg-navy-950 text-white md:flex">
      <div className="px-5 py-5">
        <Logo size={34} />
      </div>
      <nav aria-label="Navegación principal" className="flex-1 space-y-0.5 px-3">
        {NAV.filter((i) => i.roles.includes(role)).map((item) =>
          item.ready ? (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-md px-3 py-2 text-sm font-medium text-white/90 hover:bg-white/10"
            >
              {item.label}
            </Link>
          ) : (
            <span
              key={item.href}
              aria-disabled
              className="flex items-center justify-between rounded-md px-3 py-2 text-sm text-white/35"
            >
              {item.label}
              <span className="font-mono text-[10px] uppercase tracking-wider">pronto</span>
            </span>
          ),
        )}
      </nav>
      <p className="px-5 py-4 text-[11px] leading-relaxed text-white/40">
        La app no reemplaza la línea de emergencias 123.
      </p>
    </aside>
  );
}
