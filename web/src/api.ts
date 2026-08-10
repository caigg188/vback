let csrf = "";

export function setCSRF(value: string) { csrf = value; }

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  if (options.body) headers.set("Content-Type", "application/json");
  if (csrf && !["GET", "HEAD"].includes(options.method || "GET")) headers.set("X-CSRF-Token", csrf);
  const response = await fetch(`/api/v1${path}`, { ...options, headers, credentials: "same-origin" });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) throw new Error(payload?.error || `Request failed (${response.status})`);
  return payload as T;
}

export const post = <T>(path: string, value: unknown = {}) =>
  api<T>(path, { method: "POST", body: JSON.stringify(value) });
