// src/lib/adminSession.ts
// The Convex backend authorises every admin operation from the admin's own session token
// (no admin id is trusted on its own). Pages attach it with `adminFetch`; API routes read it
// with `sessionFromRequest` and forward it to Convex.

export const SESSION_HEADER = "x-vektolux-session";

/** Browser: fetch() that attaches the logged-in admin's session token as a header (never in the URL). */
export function adminFetch(input: string, init: RequestInit = {}): Promise<Response> {
  let token = "";
  try {
    const raw = typeof window !== "undefined" ? window.sessionStorage.getItem("adminSession") : null;
    token = raw ? (JSON.parse(raw)?.user?.sessionToken ?? "") : "";
  } catch {
    token = "";
  }
  const headers = new Headers(init.headers);
  if (token) headers.set(SESSION_HEADER, token);
  return fetch(input, { ...init, headers });
}

/** Server (API route): the admin session token sent by `adminFetch`, if any. */
export function sessionFromRequest(request: Request): string | undefined {
  const t = request.headers.get(SESSION_HEADER)?.trim();
  return t ? t : undefined;
}
