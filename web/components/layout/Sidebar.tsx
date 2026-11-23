"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/brand/Logo";
import type { RoleCode } from "@/types/auth";

type NavItem = { href: string; label: string; roles: readonly RoleCode[]; icon: string };

const ALL: readonly RoleCode[] = ["operador", "supervisor", "administrador"];

export const NAV: NavItem[] = [
  { href: "/", label: "Panel principal", roles: ALL, icon: "M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z" },
  { href: "/mapa", label: "Mapa territorial", roles: ALL, icon: "m9 4-6 2v14l6-2 6 2 6-2V4l-6 2-6-2Zm0 0v14m6-12v14" },
  { href: "/incidentes", label: "Bandeja de incidentes", roles: ALL, icon: "M4 4h16v10h-4l-2 3h-4l-2-3H4V4Zm0 10v6h16v-6" },
  { href: "/estadisticas", label: "Estadísticas", roles: ["supervisor", "administrador"], icon: "M4 20V10m6 10V4m6 16v-7m4 7H2" },
  { href: "/administracion", label: "Administración", roles: ["administrador"], icon: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm7.4-3a7.4 7.4 0 0 0-.1-1.3l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2.2-1.3L14.4 3h-4l-.4 2.5a7 7 0 0 0-2.2 1.3l-2.4-1-2 3.4 2 1.6a7.4 7.4 0 0 0 0 2.6l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2.2 1.3l.4 2.5h4l.4-2.5a7 7 0 0 0 2.2-1.3l2.4 1 2-3.4-2-1.6c.1-.4.1-.9.1-1.3Z" },
  { href: "/estado", label: "Estado de la plataforma", roles: ALL, icon: "M3 12h4l3-8 4 16 3-8h4" },
];

export function isActive(pathname: string, href: string) {
  return href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`);
}

export function Sidebar({ role }: { role: RoleCode }) {
  const pathname = usePathname();
  return (
    <aside className="hidden w-64 shrink-0 flex-col bg-navy-950 text-white md:flex">
      <div className="px-5 py-5">
        <Logo size={34} />
      </div>
      <nav aria-label="Navegación principal" className="flex-1 space-y-0.5 px-3">
        {NAV.filter((i) => i.roles.includes(role)).map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={`flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition ${
                active ? "bg-white/12 text-white" : "text-white/75 hover:bg-white/8 hover:text-white"
              }`}
            >
              <svg viewBox="0 0 24 24" className={`size-4.5 shrink-0 ${active ? "text-signal" : "text-white/50"}`} fill="none"
                stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d={item.icon} />
              </svg>
              {item.label}
            </Link>
          );
        })}
      </nav>
      <p className="px-5 py-4 text-[11px] leading-relaxed text-white/40">
        La plataforma no reemplaza la línea de emergencias 123.
      </p>
    </aside>
  );
}

/** Navegación compacta para pantallas pequeñas. */
export function MobileNav({ role }: { role: RoleCode }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Navegación" className="flex gap-1 overflow-x-auto border-b border-line bg-surface px-3 py-2 md:hidden">
      {NAV.filter((i) => i.roles.includes(role)).map((item) => (
        <Link key={item.href} href={item.href}
          className={`whitespace-nowrap rounded-md px-3 py-1.5 text-xs font-semibold ${
            isActive(pathname, item.href) ? "bg-navy-900 text-white" : "text-navy-900 hover:bg-bg"
          }`}>
          {item.label}
        </Link>
      ))}
    </nav>
  );
}
