"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

export function LoginForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setPending(true);
    const form = new FormData(e.currentTarget);
    const { error } = await createClient().auth.signInWithPassword({
      email: String(form.get("email") ?? "").trim(),
      password: String(form.get("password") ?? ""),
    });
    setPending(false);
    if (error) {
      // Mensaje genérico: no revela si el correo existe
      setError("Correo o contraseña incorrectos.");
      return;
    }
    router.replace("/");
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5" noValidate>
      <div className="space-y-1.5">
        <label htmlFor="email" className="block text-sm font-semibold text-navy-900">
          Correo institucional
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="username"
          required
          className="w-full rounded-lg border border-line bg-white px-3.5 py-2.5 text-ink outline-none transition focus:border-signal focus:ring-2 focus:ring-signal/25"
        />
      </div>
      <div className="space-y-1.5">
        <label htmlFor="password" className="block text-sm font-semibold text-navy-900">
          Contraseña
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          className="w-full rounded-lg border border-line bg-white px-3.5 py-2.5 text-ink outline-none transition focus:border-signal focus:ring-2 focus:ring-signal/25"
        />
      </div>
      {error && (
        <p role="alert" className="rounded-md border border-danger/30 bg-danger/5 px-3 py-2 text-sm text-danger">
          {error}
        </p>
      )}
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-navy-900 px-4 py-2.5 font-semibold text-white transition hover:bg-navy-800 disabled:opacity-60"
      >
        {pending ? "Verificando…" : "Ingresar"}
      </button>
    </form>
  );
}
