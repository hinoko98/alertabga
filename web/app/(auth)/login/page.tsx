import type { Metadata } from "next";
import { LoginForm } from "@/components/auth/LoginForm";
import { Logo } from "@/components/brand/Logo";

export const metadata: Metadata = { title: "Ingreso" };

export default function LoginPage() {
  return (
    <main className="grid min-h-dvh lg:grid-cols-[1.1fr_1fr]">
      <section className="relative hidden overflow-hidden bg-navy-950 p-12 text-white lg:flex lg:flex-col lg:justify-between">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-[0.12]"
          style={{
            backgroundImage:
              "linear-gradient(var(--cyan-500) 1px, transparent 1px), linear-gradient(90deg, var(--cyan-500) 1px, transparent 1px)",
            backgroundSize: "44px 44px",
          }}
        />
        <Logo size={44} />
        <div className="relative max-w-md space-y-4">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-signal-soft">Panel institucional</p>
          <h1 className="text-4xl font-bold leading-tight">Reportes ciudadanos, gestión y análisis territorial.</h1>
          <p className="text-white/70">
            Acceso exclusivo para personal autorizado. Toda actividad queda registrada en auditoría.
          </p>
        </div>
        <p className="relative text-xs text-white/50">
          Bucaramanga, Santander · Tratamiento de datos conforme a la Ley 1581 de 2012
        </p>
      </section>

      <section className="flex items-center justify-center px-4 py-12">
        <div className="w-full max-w-sm space-y-8">
          <div className="lg:hidden">
            <Logo size={40} tone="dark" />
          </div>
          <div className="space-y-1">
            <h2 className="text-2xl font-bold text-navy-900">Ingresar</h2>
            <p className="text-sm text-muted">Use las credenciales asignadas por su administrador.</p>
          </div>
          <LoginForm />
        </div>
      </section>
    </main>
  );
}
