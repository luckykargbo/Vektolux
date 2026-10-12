// Dashboard edge middleware + session helpers: what an unauthenticated or forged request can reach.
import { describe, expect, test } from "vitest";
import { NextRequest } from "next/server";
import { middleware } from "./middleware";
import { ADMIN_COOKIE_NAME, sessionFromRequest } from "./lib/adminSession";

const req = (path: string, init: { cookie?: string; headers?: Record<string, string>; method?: string } = {}) =>
  new NextRequest(`https://dash.example.test${path}`, {
    method: init.method ?? "GET",
    headers: { ...(init.cookie ? { cookie: init.cookie } : {}), ...(init.headers ?? {}) },
  });
const cookie = (v: string) => `${ADMIN_COOKIE_NAME}=${v}`;

describe("middleware: API routes", () => {
  test("every API route except login is 401 without the HttpOnly cookie", async () => {
    for (const p of ["/api/users", "/api/finance", "/api/payments", "/api/escrow", "/api/roles", "/api/seed", "/api/auth/me", "/api/admin/send-notification"]) {
      const res = middleware(req(p));
      expect(res.status, p).toBe(401);
      expect((await res.json()).code).toBe("UNAUTHORIZED");
    }
  });

  test("login stays reachable without a session", () => {
    const res = middleware(req("/api/auth/login", { method: "POST" }));
    expect(res.status).toBe(200); // NextResponse.next()
    expect(res.headers.get("x-middleware-next")).toBe("1");
  });

  test("a session HEADER (the old mechanism) is not accepted: only the cookie counts", () => {
    const res = middleware(req("/api/users", { headers: { "x-vektolux-session": "stolen-or-forged-token" } }));
    expect(res.status).toBe(401);
    const res2 = middleware(req("/api/users", { headers: { authorization: "Bearer abc" } }));
    expect(res2.status).toBe(401);
  });

  test("with the cookie the request passes through (Convex then validates the token itself)", () => {
    const res = middleware(req("/api/users", { cookie: cookie("sometoken") }));
    expect(res.headers.get("x-middleware-next")).toBe("1");
  });

  test("an empty / whitespace cookie is no session", () => {
    expect(middleware(req("/api/users", { cookie: cookie("   ") })).status).toBe(401);
    expect(middleware(req("/api/users", { cookie: cookie("") })).status).toBe(401);
  });
});

describe("middleware: pages", () => {
  test("dashboard pages redirect to /login with the target, never render", () => {
    const res = middleware(req("/dashboard/finance"));
    expect(res.status).toBe(307);
    const loc = new URL(res.headers.get("location")!);
    expect(loc.pathname).toBe("/login");
    expect(loc.searchParams.get("from")).toBe("/dashboard/finance");
  });

  test("an expired cookie arriving with ?from= does not loop between /login and /dashboard", () => {
    const res = middleware(req("/login?from=/dashboard", { cookie: cookie("expired") }));
    expect(res.headers.get("x-middleware-next")).toBe("1");
  });

  test("a signed-in visitor on /login is sent to the dashboard", () => {
    const res = middleware(req("/login", { cookie: cookie("tok") }));
    expect(res.status).toBe(307);
    expect(new URL(res.headers.get("location")!).pathname).toBe("/dashboard");
  });
});

describe("sessionFromRequest", () => {
  const r = (c?: string, h: Record<string, string> = {}) =>
    new Request("https://dash.example.test/api/x", { headers: { ...(c ? { cookie: c } : {}), ...h } });

  test("reads only the named cookie", () => {
    expect(sessionFromRequest(r(`a=1; ${cookie("tok123")}; b=2`))).toBe("tok123");
    expect(sessionFromRequest(r(`other=tok123`))).toBeUndefined();
    expect(sessionFromRequest(r(undefined, { "x-vektolux-session": "tok" }))).toBeUndefined();
  });

  test("a look-alike cookie name does not match", () => {
    expect(sessionFromRequest(r(`x${ADMIN_COOKIE_NAME}=evil`))).toBeUndefined();
    expect(sessionFromRequest(r(`${ADMIN_COOKIE_NAME}x=evil`))).toBeUndefined();
  });
});
