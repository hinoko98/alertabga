"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

/** Error de la API con el mensaje en español que devuelve FastAPI (`detail`). */
export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

async function token(): Promise<string | null> {
  const { data } = await createClient().auth.getSession();
  return data.session?.access_token ?? null;
}

function messageFor(status: number, detail: unknown): string {
  if (typeof detail === "string") return detail;
  if (status === 401) return "Su sesión venció. Vuelva a ingresar.";
  if (status === 403) return "No tiene permiso para esta acción.";
  if (status === 404) return "No encontrado.";
  if (status === 422) return "Revise los datos ingresados.";
  if (status >= 500) return "El servidor no respondió. Intente de nuevo.";
  return `Error ${status}`;
}

/** Llama a la API Python (`/api/py/...`) con el JWT de Supabase del funcionario. */
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const t = await token();
  if (!t) throw new ApiError(401, messageFor(401, null));
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${t}`);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  let res: Response;
  try {
    res = await fetch(`/api/py${path}`, { ...init, headers, cache: "no-store" });
  } catch {
    throw new ApiError(0, "No hay conexión con la API. ¿Está encendido el backend (docker compose up -d)?");
  }
  if (!res.ok) {
    let detail: unknown = null;
    try {
      detail = (await res.json()).detail;
    } catch {
      /* sin cuerpo JSON */
    }
    throw new ApiError(res.status, messageFor(res.status, detail));
  }
  if (res.status === 204) return undefined as T;
  const type = res.headers.get("content-type") ?? "";
  return (type.includes("application/json") ? res.json() : res.text()) as Promise<T>;
}

export const post = <T,>(path: string, body?: unknown) =>
  api<T>(path, { method: "POST", body: body === undefined ? undefined : JSON.stringify(body) });
export const patch = <T,>(path: string, body: unknown) => api<T>(path, { method: "PATCH", body: JSON.stringify(body) });
export const put = <T,>(path: string, body: unknown) => api<T>(path, { method: "PUT", body: JSON.stringify(body) });

/** Descarga un archivo protegido (p. ej. CSV) usando el token del funcionario. */
export async function download(path: string, filename: string) {
  const text = await api<string>(path);
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

type State<T> = { data: T | null; error: ApiError | null; loading: boolean };

/**
 * Lee un recurso de la API; con `refreshMs` se actualiza solo (tiempo casi real por consulta periódica).
 * `path = null` no consulta nada.
 */
export function useApi<T>(path: string | null, refreshMs?: number) {
  const [state, setState] = useState<State<T>>({ data: null, error: null, loading: path !== null });
  const current = useRef(path);
  current.current = path;

  const load = useCallback(
    async (silent = false) => {
      if (!path) return;
      if (!silent) setState((s) => ({ ...s, loading: true }));
      try {
        const data = await api<T>(path);
        if (current.current === path) setState({ data, error: null, loading: false });
      } catch (e) {
        if (current.current === path)
          setState((s) => ({ ...s, error: e instanceof ApiError ? e : new ApiError(0, String(e)), loading: false }));
      }
    },
    [path],
  );

  useEffect(() => {
    void load();
    if (!refreshMs || !path) return;
    const id = window.setInterval(() => {
      if (document.visibilityState === "visible") void load(true);
    }, refreshMs);
    return () => window.clearInterval(id);
  }, [load, refreshMs, path]);

  return { ...state, reload: () => load(true) };
}
