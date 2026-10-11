// src/lib/adminSession.ts
// Strict cookie-based HttpOnly admin session handling (no header fallback).

export const ADMIN_COOKIE_NAME = "vx_admin_session";
export const SESSION_MAX_AGE_SECONDS = 8 * 60 * 60; // 8 hours

/** Browser: fetch() that attaches credentials (HttpOnly cookie) to same-origin requests. */
export function adminFetch(input: string, init: RequestInit = {}): Promise<Response> {
  return fetch(input, {
    ...init,
    credentials: "same-origin",
  });
}

/** Server (API route / middleware): extracts session token strictly from HttpOnly cookie. */
export function sessionFromRequest(request: Request): string | undefined {
  const cookieHeader = request.headers.get("cookie");
  if (!cookieHeader) return undefined;

  const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${ADMIN_COOKIE_NAME}=([^;]+)`));
  if (match && match[1]?.trim()) {
    return decodeURIComponent(match[1].trim());
  }

  return undefined;
}

