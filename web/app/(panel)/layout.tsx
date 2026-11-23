import { redirect } from "next/navigation";
import { SignOutButton } from "@/components/auth/SignOutButton";
import { Logo } from "@/components/brand/Logo";
import { SessionProvider } from "@/components/layout/SessionProvider";
import { MobileNav, Sidebar } from "@/components/layout/Sidebar";
import { Topbar } from "@/components/layout/Topbar";
import { getSessionState } from "@/services/session";

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const session = await getSessionState();

  if (session.kind === "anonymous") redirect("/login");

  if (session.kind === "forbidden") {
    return (
      <main className="flex min-h-dvh items-center justify-center bg-navy-950 px-4">
        <div className="w-full max-w-md space-y-5 rounded-2xl bg-surface p-8 text-center">
          <div className="flex justify-center">
            <Logo size={40} tone="dark" />
          </div>
          <h1 className="text-xl font-bold text-navy-900">Sin acceso al panel institucional</h1>
          <p className="text-sm text-muted">
            La cuenta {session.email ?? ""} no tiene un rol institucional activo. Los ciudadanos usan la aplicación
            móvil AlertaBGA para reportar y hacer seguimiento.
          </p>
          <SignOutButton className="bg-navy-900 text-white hover:bg-navy-800" />
        </div>
      </main>
    );
  }

  return (
    <SessionProvider profile={session.profile}>
      <div className="flex min-h-dvh">
        <Sidebar role={session.profile.role} />
        <div className="flex min-w-0 flex-1 flex-col">
          <Topbar profile={session.profile} />
          <MobileNav role={session.profile.role} />
          <main className="flex-1 px-4 py-6 md:px-8">{children}</main>
        </div>
      </div>
    </SessionProvider>
  );
}
