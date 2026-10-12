// Admin login route: what is forwarded to Convex, what the browser gets, and what it never gets.
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const mutation = vi.fn();
vi.mock("convex/browser", () => ({
  ConvexHttpClient: class {
    mutation = mutation;
  },
}));
vi.mock("@/lib/convex", () => ({ CONVEX_URL: "https://unit-test.convex.cloud" }));

import { POST } from "./route";

const call = (body: unknown, headers: Record<string, string> = {}) =>
  POST(new Request("https://dash.example.test/api/auth/login", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  }));
const ok = (o: Record<string, unknown> = {}) => ({
  success: true, userId: "u1", sessionToken: "SECRET-SESSION-TOKEN", name: "Boss", email: "boss@x.test", role: "admin", ...o,
});

beforeEach(() => {
  mutation.mockReset();
  vi.stubEnv("LOGIN_PROXY_SECRET", "");
  vi.stubEnv("TRUSTED_CLIENT_IP_HEADER", "");
});
afterEach(() => vi.unstubAllEnvs());

describe("forwarding to Convex", () => {
  test("by default NO client address and no proxy secret are sent (caller-controlled headers are not trusted)", async () => {
    mutation.mockResolvedValue(ok());
    await call({ email: "boss@x.test", password: "pw" }, { "x-forwarded-for": "6.6.6.6", "cf-connecting-ip": "7.7.7.7" });
    const args = mutation.mock.calls[0][1];
    expect(args).not.toHaveProperty("ip");
    expect(args).not.toHaveProperty("proxySecret");
  });

  test("with the proxy secret configured it is sent, still without an address", async () => {
    vi.stubEnv("LOGIN_PROXY_SECRET", "0123456789abcdef-secret");
    mutation.mockResolvedValue(ok());
    await call({ email: "boss@x.test", password: "pw" }, { "x-forwarded-for": "6.6.6.6" });
    const args = mutation.mock.calls[0][1];
    expect(args.proxySecret).toBe("0123456789abcdef-secret");
    expect(args).not.toHaveProperty("ip");
  });

  test("the address comes only from the ONE header the operator named, and only if well-formed", async () => {
    vi.stubEnv("LOGIN_PROXY_SECRET", "0123456789abcdef-secret");
    vi.stubEnv("TRUSTED_CLIENT_IP_HEADER", "cf-connecting-ip");
    mutation.mockResolvedValue(ok());
    await call({ email: "boss@x.test", password: "pw" }, { "cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "6.6.6.6" });
    expect(mutation.mock.calls[0][1].ip).toBe("203.0.113.9");

    mutation.mockClear();
    await call({ email: "boss@x.test", password: "pw" }, { "cf-connecting-ip": "not an ip; DROP" });
    expect(mutation.mock.calls[0][1]).not.toHaveProperty("ip");
  });

  test("a trusted header without the proxy secret forwards nothing (Convex would ignore it anyway)", async () => {
    vi.stubEnv("TRUSTED_CLIENT_IP_HEADER", "cf-connecting-ip");
    mutation.mockResolvedValue(ok());
    await call({ email: "boss@x.test", password: "pw" }, { "cf-connecting-ip": "203.0.113.9" });
    expect(mutation.mock.calls[0][1]).not.toHaveProperty("ip");
  });
});

describe("what the browser receives", () => {
  test("an admin gets an HttpOnly, SameSite=Strict cookie and the token is NOT in the JSON body", async () => {
    mutation.mockResolvedValue(ok());
    const res = await call({ email: "boss@x.test", password: "pw" });
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(text).not.toContain("SECRET-SESSION-TOKEN");
    const setCookie = res.headers.get("set-cookie") ?? "";
    expect(setCookie).toContain("vx_admin_session=SECRET-SESSION-TOKEN");
    expect(setCookie.toLowerCase()).toContain("httponly");
    expect(setCookie.toLowerCase()).toContain("samesite=strict");
  });

  test("a valid NON-admin account is refused with the same answer as a wrong password, and gets no cookie", async () => {
    mutation.mockResolvedValue(ok({ role: "client" }));
    const res = await call({ email: "cust@x.test", password: "pw" });
    expect(res.status).toBe(401);
    expect(res.headers.get("set-cookie")).toBeNull();
    const body = await res.json();
    mutation.mockResolvedValue({ success: false, errorMessage: "Invalid email/phone or password." });
    const wrong = await (await call({ email: "cust@x.test", password: "nope" })).json();
    expect(body.error).toBe(wrong.error);
  });

  test("2FA required is surfaced without a session; a lockout becomes 429; internals never leak", async () => {
    mutation.mockResolvedValue({ success: false, mfaRequired: true, errorMessage: "Two-factor authentication code required." });
    const mfa = await call({ email: "boss@x.test", password: "pw" });
    expect(mfa.status).toBe(200);
    expect((await mfa.json()).mfaRequired).toBe(true);
    expect(mfa.headers.get("set-cookie")).toBeNull();

    mutation.mockResolvedValue({ success: false, errorMessage: "Too many failed attempts. Please try again in 15 minute(s)." });
    expect((await call({ email: "boss@x.test", password: "pw" })).status).toBe(429);

    mutation.mockRejectedValue(new Error("convex internal: secret table users failed at line 12"));
    const boom = await call({ email: "boss@x.test", password: "pw" });
    expect(boom.status).toBe(500);
    expect(await boom.text()).not.toMatch(/convex internal|table users/);
  });

  test("missing credentials never reach Convex", async () => {
    expect((await call({ email: "boss@x.test" })).status).toBe(400);
    expect((await call({})).status).toBe(400);
    expect(mutation).not.toHaveBeenCalled();
  });
});
