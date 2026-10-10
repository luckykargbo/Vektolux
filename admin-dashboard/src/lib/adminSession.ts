// src/lib/adminSession.ts
// Cookie-based HttpOnly admin session handling with backward-compatible header support.

export const ADMIN_COOKIE_NAME = "vx_admin_session";
export const SESSION_HEADER = "x-vektolux-session";
export const SESSION_MAX_AGE_SECONDS = 8 * 60 * 60; // 8 hours

/** Browser: fetch() that attaches credentials (HttpOnly cookie) and optional header. */
export function adminFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  try {
    const raw = typeof window !== "undefined" ? window.sessionStorage.getItem("adminSession") : null;
    const token = raw ? (JSON.parse(raw)?.user?.sessionToken ?? "") : "";
    if (token) headers.set(SESSION_HEADER, token);
  } catch {
    // ignore
  }

  return fetch(input, {
    ...init,
    headers,
    credentials: "same-origin",
  });
}

/** Server (API route / middleware): extracts session token from HttpOnly cookie or header. */
export function sessionFromRequest(request: Request): string | undefined {
  // 1. Primary: HttpOnly cookie vx_admin_session
  const cookieHeader = request.headers.get("cookie");
  if (cookieHeader) {
    const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${ADMIN_COOKIE_NAME}=([^;]+)`));
    if (match && match[1]?.trim()) {
      return decodeURIComponent(match[1].trim());
    }
  }

  // 2. Fallback: x-vektolux-session header
  const headerToken = request.headers.get(SESSION_HEADER)?.trim();
  if (headerToken) return headerToken;

  return undefined;
}

