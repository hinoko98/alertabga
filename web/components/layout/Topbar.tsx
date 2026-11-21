import { SignOutButton } from "@/components/auth/SignOutButton";
import { ROLE_LABEL, type StaffProfile } from "@/types/auth";

export function Topbar({ profile, title }: { profile: StaffProfile; title: string }) {
  return (
    <header className="flex items-center justify-between gap-4 border-b border-line bg-surface px-4 py-3 md:px-8">
      <h1 className="truncate text-lg font-bold text-navy-900">{title}</h1>
      <div className="flex items-center gap-3">
        <div className="text-right leading-tight">
          <p className="text-sm font-semibold text-ink">{profile.fullName ?? profile.email}</p>
          <p className="font-mono text-[11px] uppercase tracking-wider text-muted">{ROLE_LABEL[profile.role]}</p>
        </div>
        <SignOutButton className="border border-line text-navy-900 hover:bg-bg" />
      </div>
    </header>
  );
}
