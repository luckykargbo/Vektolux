/// <reference types="vite/client" />
// Untrusted text in transactional email HTML, and the escape helpers behind it.
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { escapeHtml, safeDisplayNameForHtml } from "./lib/html";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);

describe("escapeHtml / safeDisplayNameForHtml", () => {
  test("neutralises markup, attributes and entities", () => {
    const out = escapeHtml(`<a href="https://evil/?x=1&y='2'">\`click\`</a>`);
    expect(out).not.toMatch(/[<>"'`]/);
    expect(out).toContain("&lt;a");
    expect(out).toContain("&amp;");
  });
  test("display name: control / bidi characters stripped, length bounded", () => {
    const out = safeDisplayNameForHtml(`A\u0000B‮C\n\tD ${"x".repeat(200)}`);
    expect(out).not.toMatch(/[\u0000-\u001f‮]/);
    expect(out.length).toBeLessThanOrEqual(60);
  });
  test("non-strings are tolerated", () => {
    expect(escapeHtml(undefined)).toBe("");
    expect(safeDisplayNameForHtml(null)).toBe("");
  });
});

describe("sendOtpEmail", () => {
  let sent: any[] = [];
  beforeEach(() => {
    sent = [];
    vi.stubEnv("RESEND_API_KEY", "re_test_key_not_real");
    vi.stubGlobal("fetch", async (_url: string, init: any) => {
      sent.push(JSON.parse(init.body));
      return new Response(JSON.stringify({ id: "msg_1" }), { status: 200 });
    });
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  test("an attacker-chosen name is escaped in the HTML body", async () => {
    const t = convexTest(schema, modules);
    await t.action(internal.emails.sendOtpEmail, {
      to: "victim@example.test", otpCode: "123456",
      recipientName: `<a href="https://phish.example/verify">Verify your account</a><script>x()</script>`,
    });
    expect(sent).toHaveLength(1);
    const html: string = sent[0].html;
    expect(html).not.toContain("<a href");
    expect(html).not.toContain("<script");
    expect(html).toContain("&lt;a");
    expect(html).toContain("123456");
  });

  test("a non-numeric code is never sent (cannot inject through the code or subject)", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.action(internal.emails.sendOtpEmail, {
      to: "victim@example.test", otpCode: `1</span><img src=x onerror=1>`, recipientName: "A",
    });
    expect(r.success).toBe(false);
    expect(sent).toHaveLength(0);
  });
});
