// convex/lib/monimeWebhook.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Monime webhook request authentication.
//
// SCHEME (header name is from Monime's published "Standard headers" page; the field layout and the
// signed string are from the community TypeScript SDK that cites Monime's HMAC guide — Monime's own
// HMAC page is still an unpublished stub, so this MUST be confirmed against the first real delivery):
//
//   Header   : Monime-Signature: t=<unix-seconds>,v1=<base64 of the 32-byte HMAC>
//              exactly two components, no others
//   Signed   : the ASCII bytes  "<t>_"  followed by the EXACT raw request body bytes
//   Algorithm: HMAC-SHA-256, key = the webhook secret string (UTF-8)
//   Freshness: |now − t| must be ≤ 300 seconds (replay window)
//
// The raw body is verified as received (ArrayBuffer): it is never parsed and re-serialised, and not
// even decoded to a string, before verification. The comparison uses WebCrypto `verify`
// (constant-time). Secrets are read from server-side Convex environment variables only and are
// never logged or returned; callers log only the coarse `reason` code below, never a value.
// ═══════════════════════════════════════════════════════════════════════

export const SIGNATURE_TOLERANCE_SECONDS = 300;

export type MonimeVerification =
  | { ok: true }
  | { ok: false; reason: "no_secret" | "missing_header" | "header_format" | "timestamp" | "mismatch" };

/**
 * The secrets accepted right now: MONIME_WEBHOOK_SECRET (current) and, ONLY during a migration
 * window, MONIME_WEBHOOK_SECRET_OLD (the legacy webhook's secret). Unset/empty values are ignored.
 */
export function monimeWebhookSecrets(): string[] {
  const out: string[] = [];
  for (const name of ["MONIME_WEBHOOK_SECRET", "MONIME_WEBHOOK_SECRET_OLD"]) {
    const v = (process.env[name] ?? "").trim();
    if (v.length > 0 && !out.includes(v)) out.push(v);
  }
  return out;
}

function parseHeader(header: string): { t: string; mac: Uint8Array<ArrayBuffer> } | null {
  const parts = header.split(",");
  if (parts.length !== 2) return null;
  const seen = new Map<string, string>();
  for (const part of parts) {
    const i = part.indexOf("=");
    if (i < 1) return null;
    const key = part.slice(0, i).trim();
    const value = part.slice(i + 1).trim();
    if ((key !== "t" && key !== "v1") || seen.has(key)) return null;
    seen.set(key, value);
  }
  const t = seen.get("t");
  const v1 = seen.get("v1");
  if (t === undefined || v1 === undefined) return null;
  if (!/^(0|[1-9]\d{0,14})$/.test(t)) return null;
  // standard base64 of exactly 32 bytes: 43 chars + one "="
  if (!/^[A-Za-z0-9+/]{43}=$/.test(v1)) return null;
  let bin: string;
  try {
    bin = atob(v1);
  } catch {
    return null;
  }
  if (bin.length !== 32) return null;
  const mac = new Uint8Array(new ArrayBuffer(32));
  for (let i = 0; i < 32; i++) mac[i] = bin.charCodeAt(i);
  return { t, mac };
}

export async function verifyMonimeSignature(
  rawBody: Uint8Array,
  header: string | null,
  secrets: string[],
  nowMs: number = Date.now()
): Promise<MonimeVerification> {
  if (secrets.length === 0) return { ok: false, reason: "no_secret" };
  if (header === null || header.trim() === "") return { ok: false, reason: "missing_header" };
  const parsed = parseHeader(header);
  if (!parsed) return { ok: false, reason: "header_format" };

  const ageSeconds = Math.abs(Math.floor(nowMs / 1000) - Number(parsed.t));
  if (!(ageSeconds <= SIGNATURE_TOLERANCE_SECONDS)) return { ok: false, reason: "timestamp" };

  const prefix = new TextEncoder().encode(`${parsed.t}_`);
  const data = new Uint8Array(new ArrayBuffer(prefix.length + rawBody.length));
  data.set(prefix, 0);
  data.set(rawBody, prefix.length);

  // Every configured secret is tried (no early exit) so timing does not reveal which one matched.
  let matched = false;
  for (const secret of secrets) {
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
    const ok = await crypto.subtle.verify("HMAC", key, parsed.mac, data);
    matched = matched || ok;
  }
  return matched ? { ok: true } : { ok: false, reason: "mismatch" };
}
