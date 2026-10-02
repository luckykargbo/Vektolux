// convex/http.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — HTTP Actions: Payment Gateway Initialization & Webhooks
// Exposes:
//   Provider webhooks only (Monime, Orange Money, eIDV). The unused Paystack/Flutterwave
//   payment-intent path (/payments/webhook) was removed: no such provider was configured and its
//   commission was chosen by the client.
// ═══════════════════════════════════════════════════════════════════════

import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal, api } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { monimeWebhookSecrets, verifyMonimeSignature } from "./lib/monimeWebhook";
import {
  sanitizeSierraLeonePhone,
  parseCarrierResponse,
  logGatewayError,
} from "./lib/paymentErrors";

// ─── HTTP SURFACE (audited) ───────────────────────────────────────────
// Only provider webhooks are exposed: eIDV (/api/v1/verifications/webhook, HMAC), Orange Money
// (secret required) and Monime (re-verified through Monime's API). App features call Convex
// functions directly with the user's session. Unauthenticated REST duplicates — including two
// "escrow webhooks" that let anyone mark an escrow as funded — were removed.
const http = httpRouter();

// ═══════════════════════════════════════════════════════════════════════
//          POST /payments/initialize — Gateway Checkout Init
// ═══════════════════════════════════════════════════════════════════════



// ── CORS preflight for /payments/* routes ────────────────────────────

// ═══════════════════════════════════════════════════════════════════════
//          POST /api/payments/topup — Escrow Wallet Top-Up Endpoint
// ═══════════════════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════════════════
//          GET /api/user/wallet-profile — Dynamic Profile & Wallet State
// ═══════════════════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════════════════
//                    GATEWAY API IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════


/**
 * CORS headers for cross-origin requests from the Flutter app.
 */
// Every remaining HTTP route is a server-to-server provider webhook, so no cross-origin browser
// access is granted (previously "Access-Control-Allow-Origin: *"). Name kept for the call sites.
function corsHeaders(): Record<string, string> {
  return { "Content-Type": "application/json" };
}

// ═══════════════════════════════════════════════════════════════════════
//   POST /api/v1/verifications/webhook — Cryptographically Verified eIDV
// ═══════════════════════════════════════════════════════════════════════

// No default secret: a committed default is a public secret. Unset => every request is rejected.
const EIDV_WEBHOOK_SECRET = process.env.EIDV_WEBHOOK_SECRET || "";

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

async function verifyEidvSignature(
  rawBody: string,
  providedSignature: string,
  secret: string
): Promise<boolean> {
  if (!secret || !providedSignature) return false;
  try {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const cryptoKey = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const signatureBuffer = await crypto.subtle.sign(
      "HMAC",
      cryptoKey,
      encoder.encode(rawBody)
    );

    const hashArray = Array.from(new Uint8Array(signatureBuffer));
    const computedSignature = hashArray
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    return timingSafeEqual(computedSignature, providedSignature);
  } catch {
    return false;
  }
}

http.route({
  path: "/api/v1/verifications/webhook",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const signature = request.headers.get("x-signature") || request.headers.get("x-smile-signature");
      const eventId = request.headers.get("x-event-id") || request.headers.get("x-webhook-id");
      const rawBody = await request.text();

      // 1. Signature Verification
      if (!signature) {
        return new Response(
          JSON.stringify({ error: "Missing required cryptographic signature" }),
          { status: 401, headers: corsHeaders() }
        );
      }

      const isValid = await verifyEidvSignature(rawBody, signature, EIDV_WEBHOOK_SECRET);
      if (!isValid) {
        return new Response(
          JSON.stringify({ error: "Invalid HMAC-SHA256 signature" }),
          { status: 403, headers: corsHeaders() }
        );
      }

      // 2. Parse Payload
      const payload = JSON.parse(rawBody);
      const {
        referenceId,
        provider = "smile_id",
        resultCode,
        isSuccess,
        livenessPassed,
        faceMatchScore,
        livenessScore,
        mrzValid,
        tamperCheckPassed,
        failureReason,
      } = payload;

      if (!referenceId) {
        return new Response(
          JSON.stringify({ error: "referenceId is required in payload" }),
          { status: 400, headers: corsHeaders() }
        );
      }

      const idempotencyKey = eventId ?? `sig_${signature.substring(0, 32)}_${referenceId}`;

      // 3. Pass Criteria Evaluation:
      // Must pass 3D liveness, face match (>85%), and anti-tamper check
      const isApproved =
        isSuccess === true &&
        livenessPassed === true &&
        (faceMatchScore ?? 1.0) >= 0.85 &&
        tamperCheckPassed !== false;

      // 4. Trigger Internal Atomic Transition
      const transitionResult = await ctx.runMutation(
        internal.verification.applyWebhookTransition,
        {
          referenceId,
          idempotencyKey,
          provider,
          isApproved,
          livenessScore: livenessScore ?? (livenessPassed ? 0.99 : 0.0),
          faceMatchScore: faceMatchScore ?? (isSuccess ? 0.95 : 0.0),
          mrzValidated: mrzValid ?? true,
          tamperingPassed: tamperCheckPassed ?? true,
          rejectionReason: isApproved ? undefined : (failureReason ?? "Verification criteria not met."),
          rawResultCode: resultCode ?? "PROCESSED",
          diagnosticPayload: JSON.stringify({
            resultCode,
            livenessScore,
            faceMatchScore,
            timestamp: Date.now(),
          }),
        }
      );

      return new Response(
        JSON.stringify({
          received: true,
          status: isApproved ? "VERIFIED" : "REJECTED",
          alreadyHandled: transitionResult.alreadyHandled,
        }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (err: any) {
      return new Response(
        JSON.stringify({ error: "Internal processing error", message: err.message }),
        { status: 500, headers: corsHeaders() }
      );
    }
  }),
});


// ═══════════════════════════════════════════════════════════════════════
//   POST /webhooks/orange-money — Orange Money Sierra Leone Webhook
//   (Timing-Safe HMAC & Shared-Secret Protected)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Constant-time comparison between two strings to prevent timing side-channel attacks.
 */
function timingSafeEqualStr(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const bufA = enc.encode(a);
  const bufB = enc.encode(b);
  let diff = bufA.byteLength ^ bufB.byteLength;
  const maxLen = Math.max(bufA.byteLength, bufB.byteLength);
  for (let i = 0; i < maxLen; i++) {
    const byteA = i < bufA.byteLength ? bufA[i] : 0;
    const byteB = i < bufB.byteLength ? bufB[i] : 0;
    diff |= byteA ^ byteB;
  }
  return diff === 0;
}

/**
 * Validates incoming carrier webhook signature against configured secret.
 * Supports:
 * 1. Direct shared token matching in x-orange-signature or Authorization header (timing-safe)
 * 2. HMAC-SHA256 signature calculation over raw payload (timing-safe)
 */
async function verifyCarrierSignature(
  rawBody: string,
  signatureHeader: string | null,
  authHeader: string | null,
  configuredSecret: string
): Promise<boolean> {
  const secret = (configuredSecret || "").trim();
  if (!secret) return false;

  // Check 1: Signature header token / HMAC
  if (signatureHeader) {
    const sig = signatureHeader.replace(/^sha256=/i, "").trim();

    // 1A: Direct shared secret token check (timing-safe)
    if (timingSafeEqualStr(sig, secret)) {
      return true;
    }

    // 1B: HMAC-SHA256 of raw request payload (timing-safe)
    try {
      const enc = new TextEncoder();
      const key = await crypto.subtle.importKey(
        "raw",
        enc.encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
      );
      const signatureBuffer = await crypto.subtle.sign(
        "HMAC",
        key,
        enc.encode(rawBody)
      );
      const computedHex = Array.from(new Uint8Array(signatureBuffer))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");

      if (timingSafeEqualStr(sig.toLowerCase(), computedHex.toLowerCase())) {
        return true;
      }
    } catch (e) {
      console.error("HMAC verification error:", e);
    }
  }

  // Check 2: Bearer token in Authorization header
  if (authHeader) {
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (timingSafeEqualStr(token, secret)) {
      return true;
    }
  }

  return false;
}

const handleOrangeMoneyWebhook = httpAction(async (ctx, request) => {
  try {
    // 1. Read raw body first for timing-safe HMAC verification
    let rawPayload = "";
    try {
      rawPayload = await request.text();
    } catch (_) {
      return new Response(
        JSON.stringify({
          status: "BAD_REQUEST",
          error: "Unable to read request payload",
        }),
        { status: 400, headers: corsHeaders() }
      );
    }

    // 2. Timing-safe Signature & Authorization validation
    const signature =
      request.headers.get("x-orange-signature") ||
      request.headers.get("X-Orange-Signature");
    const authHeader =
      request.headers.get("authorization") ||
      request.headers.get("Authorization");

    const configuredSecret =
      process.env.ORANGE_MONEY_WEBHOOK_SECRET || ""; // no default: unset => rejected

    const isAuthorized = await verifyCarrierSignature(
      rawPayload,
      signature,
      authHeader,
      configuredSecret
    );

    if (!isAuthorized) {
      return new Response(
        JSON.stringify({
          status: "UNAUTHORIZED",
          error: "Invalid or missing webhook signature or authorization token",
        }),
        { status: 401, headers: corsHeaders() }
      );
    }

    // 3. Parse & validate JSON body
    let body: any = {};
    try {
      body = JSON.parse(rawPayload);
    } catch (_) {
      return new Response(
        JSON.stringify({
          status: "BAD_REQUEST",
          error: "Malformed or invalid JSON payload",
        }),
        { status: 400, headers: corsHeaders() }
      );
    }

    console.log("Orange Money SL webhook received");

    // 4. Extract transaction fields across carrier conventions
    const txnId =
      body.carrierTransactionId ||
      body.txnId ||
      body.mpesa_or_om_ref ||
      body.txId ||
      body.transaction_id ||
      body.reference ||
      body.pay_token ||
      body.notif_token;

    const phoneNumber =
      body.phoneNumber ||
      body.msisdn ||
      body.phone ||
      body.customer_phone ||
      "";

    const rawAmount = body.amount ?? body.txn_amount ?? body.value;
    const amount =
      typeof rawAmount === "number" ? rawAmount : parseFloat(rawAmount);

    // A delivery with no explicit status is NOT treated as a success (it used to default to "SUCCESS").
    const status = typeof body.status === "string" ? body.status.trim() : "";
    const currency = (typeof body.currency === "string" && body.currency.trim() ? body.currency : "SLE").toString().trim().toUpperCase();

    if (!status) {
      return new Response(
        JSON.stringify({ status: "BAD_REQUEST", error: "A payment status is required." }),
        { status: 400, headers: corsHeaders() }
      );
    }
    // The Vektolux wallet is SLE-only: a credit in any other currency is refused, not converted.
    if (currency !== "SLE") {
      return new Response(
        JSON.stringify({ status: "BAD_REQUEST", error: "Unsupported currency." }),
        { status: 400, headers: corsHeaders() }
      );
    }
    if (!txnId || typeof txnId !== "string" || !Number.isFinite(amount) || amount <= 0) {
      return new Response(
        JSON.stringify({
          status: "BAD_REQUEST",
          error: "Missing required fields: valid txnId/carrierTransactionId and positive amount are required",
        }),
        { status: 400, headers: corsHeaders() }
      );
    }

    // 5. Dispatch to idempotent processIncomingCarrierDeposit mutation
    const result = await ctx.runMutation(
      internal.payments.processIncomingCarrierDeposit,
      {
        carrierTransactionId: String(txnId),
        phoneNumber: String(phoneNumber),
        amount,
        status,
        currency,
        provider: "ORANGE_MONEY_SL",
        rawPayload,
        // No userId: Vektolux never sends Orange a user id, so an identity inside the delivery would be
        // chosen by the caller. The wallet owner is resolved ONLY from the paying phone number.
      }
    );

    console.log("Orange Money SL webhook processed");
    // (error text is generic; never echo internals)

    return new Response(
      JSON.stringify({
        status: "SUCCESS",
        result,
      }),
      {
        status: 200,
        headers: corsHeaders(),
      }
    );
  } catch (err: any) {
    console.error("Orange Money SL webhook server error:", err?.message ?? "unknown");
    return new Response(
      JSON.stringify({
        status: "INTERNAL_ERROR",
        error: "Internal server error occurred",
      }),
      {
        status: 500,
        headers: corsHeaders(),
      }
    );
  }
});

// Primary route: /webhooks/orange-money
http.route({
  path: "/webhooks/orange-money",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(),
    });
  }),
});

http.route({
  path: "/webhooks/orange-money",
  method: "POST",
  handler: handleOrangeMoneyWebhook,
});

// Legacy / alias routes for backward compatibility
http.route({
  path: "/api/webhooks/orange-money",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(),
    });
  }),
});

http.route({
  path: "/api/webhooks/orange-money",
  method: "POST",
  handler: handleOrangeMoneyWebhook,
});

http.route({
  path: "/payments/orange-money/webhook",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(),
    });
  }),
});

http.route({
  path: "/payments/orange-money/webhook",
  method: "POST",
  handler: handleOrangeMoneyWebhook,
});

// ═══════════════════════════════════════════════════════════════════════
//          POST /webhooks/monime — MoniMe Webhook Receiver
//
// LAYER 1 - AUTHENTICATION (lib/monimeWebhook.ts): the Monime-Signature header (t=<unix>,v1=<base64
//   HMAC-SHA256 of "<t>_" + raw body>) is verified over the EXACT raw bytes with MONIME_WEBHOOK_SECRET
//   (and, only during a migration, MONIME_WEBHOOK_SECRET_OLD), inside a 300 s freshness window. No
//   secret configured, or any failure -> rejected, nothing processed.
// LAYER 2 - DUPLICATE PROTECTION (monimeWebhooks.ts): each event id is handled once; a retry is
//   allowed only after a failed attempt.
// LAYER 3 - THE PAYLOAD IS ONLY A HINT: it is never trusted for who gets credited, how much, or
//   whether a payout succeeded. For every relevant event we take the resource id and ask Monime's own
//   API about that resource (with our credentials), then act on THAT answer for records WE created:
//   - payment_code.* / checkout_session.* -> settleMoniMeReference (GET /payment-codes|checkout-sessions/{id})
//   - payout.*                            -> reconcilePayout        (GET /payouts/{id}; must match our withdrawal)
// LAYER 4 - every money movement is independently idempotent (provider reference / idempotency key).
//
// Envelope (docs.monime.io/guide/webhook/structure):
//   { apiVersion, event: { id, name: "<resource>.<event>", timestamp }, object: { id, type }, data }
// ═══════════════════════════════════════════════════════════════════════

/** Everything the Monime endpoint does with an event. Returns a short status label (never financial data). */
async function dispatchMoniMeEvent(
  ctx: any,
  eventName: string,
  objectId: string,
  payload: any
): Promise<string> {
  const isPmc = /^pmc-[A-Za-z0-9_-]{4,80}$/.test(objectId);
  const isPyt = /^pyt-[A-Za-z0-9_-]{4,80}$/.test(objectId);
  const isOtherId = /^[A-Za-z0-9_-]{4,80}$/.test(objectId) && !isPmc && !isPyt;

  switch (eventName) {
    // A payment code was paid / expired. The wallet is credited ONLY if Monime's own API says so.
    case "payment_code.completed":
    case "payment_code.expired": {
      if (!isPmc) return "ignored_bad_id";
      const r: any = await ctx.runAction(internal.payments.settleMoniMeReference, { reference: objectId });
      return r?.settled ? "settled" : String(r?.status ?? "checked").slice(0, 40);
    }
    // Hosted checkout (card / bank / momo): confirmed ONLY by GET /checkout-sessions/{id}.
    case "checkout_session.completed":
    case "checkout_session.expired":
    case "checkout_session.cancelled": {
      if (!isOtherId) return "ignored_bad_id";
      const r: any = await ctx.runAction(internal.payments.settleMoniMeReference, { reference: objectId });
      return r?.settled ? "settled" : String(r?.status ?? "checked").slice(0, 40);
    }
    // Payouts: the withdrawal is completed / released ONLY per GET /payouts/{id} for OUR payout.
    case "payout.completed":
    case "payout.failed":
    case "payout.delayed": {
      if (!isPyt) return "ignored_bad_id";
      // Our own withdrawal id (set as payout metadata at dispatch) lets us bind a payout whose id we
      // have not recorded yet; it is verified against Monime's record before anything is applied.
      let hint: string | undefined;
      const md = payload?.data?.metadata;
      const parsed = typeof md === "string" ? (() => { try { return JSON.parse(md); } catch { return {}; } })() : md;
      if (parsed && typeof parsed.withdrawalId === "string") hint = parsed.withdrawalId;
      const r: any = await ctx.runAction(internal.withdrawals.reconcilePayout, { payoutId: objectId, hintWithdrawalId: hint });
      return String(r?.status ?? "checked").slice(0, 40);
    }
    // Not final (processing / created) or not money-bearing for us: acknowledged, no financial effect.
    case "payment_code.processed":
    case "payment_code.created":
      return "ignored_not_final";
    case "payment.created":
    case "payment.completed":
      return "ignored_hint_only"; // payments are settled through their payment code / checkout session
    case "ussd_otp.verified":
    case "ussd_otp.expired":
      return "ignored_otp_state_is_never_taken_from_a_webhook";
    case "internal_transfer.failed":
    case "internal_transfer.completed":
      console.warn(`[MoniMe Webhook] ${eventName} received; Vektolux does not use internal transfers`);
      return "ignored_unused_feature";
    default:
      return "ignored_unknown_event";
  }
}

const handleMoniMeWebhook = httpAction(async (ctx, request) => {
  // 1. Authentication. FAIL CLOSED: without a configured secret nothing is accepted.
  //    (Settlement is still guaranteed by the 5-minute pollers.)
  const secrets = monimeWebhookSecrets();
  if (secrets.length === 0) {
    console.error("[MoniMe Webhook] MONIME_WEBHOOK_SECRET is not configured; request rejected");
    return new Response(JSON.stringify({ error: "Webhook verification is not configured" }), { status: 503, headers: corsHeaders() });
  }

  // The EXACT bytes received are verified; nothing is parsed or re-serialised first.
  let raw: Uint8Array;
  try {
    raw = new Uint8Array(await request.arrayBuffer());
  } catch {
    return new Response(JSON.stringify({ error: "Unreadable body" }), { status: 400, headers: corsHeaders() });
  }
  if (raw.length > 200_000) {
    return new Response(JSON.stringify({ error: "Payload too large" }), { status: 413, headers: corsHeaders() });
  }
  const verdict = await verifyMonimeSignature(raw, request.headers.get("monime-signature"), secrets);
  if (!verdict.ok) {
    // Only a coarse reason code is logged: never the signature, the body or a secret.
    console.warn(`[MoniMe Webhook] rejected: ${verdict.reason}`);
    return new Response(JSON.stringify({ error: "Invalid signature" }), { status: 401, headers: corsHeaders() });
  }

  // 2. The request is authentic. Parse it.
  let payload: any;
  try {
    payload = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return new Response(JSON.stringify({ error: "Malformed JSON payload" }), { status: 400, headers: corsHeaders() });
  }
  const eventName = String(payload?.event?.name ?? "").toLowerCase().slice(0, 80);
  const objectId = String(payload?.object?.id ?? "").trim().slice(0, 100);
  const eventId = typeof payload?.event?.id === "string" ? payload.event.id.trim().slice(0, 100) : "";

  // 3. Duplicate protection: the same event id (Monime retries, or the old + new webhook) runs once.
  if (eventId) {
    const claim: any = await ctx.runMutation(internal.monimeWebhooks.claimEvent, { eventId, eventName, objectId });
    if (!claim.fresh) {
      return new Response(JSON.stringify({ received: true, duplicate: true }), { status: 200, headers: corsHeaders() });
    }
  }

  // 4. Handle. The payload is only a HINT: every action re-reads the truth from Monime's API.
  try {
    const outcome = await dispatchMoniMeEvent(ctx, eventName, objectId, payload);
    if (eventId) await ctx.runMutation(internal.monimeWebhooks.finishEvent, { eventId, ok: true, outcome });
    console.log(`[MoniMe Webhook] ${eventName} -> ${outcome}`);
    return new Response(JSON.stringify({ received: true, outcome }), { status: 200, headers: corsHeaders() });
  } catch (err: any) {
    console.error("[MoniMe Webhook] processing error:", err?.message ?? "unknown");
    if (eventId) await ctx.runMutation(internal.monimeWebhooks.finishEvent, { eventId, ok: false });
    // 500 so Monime retries (same event id; the claim above allows the retry). Pollers also cover it.
    return new Response(JSON.stringify({ received: false, error: "Processing failed" }), { status: 500, headers: corsHeaders() });
  }
});

// Register /webhooks/monime
http.route({
  path: "/webhooks/monime",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }),
});

http.route({
  path: "/webhooks/monime",
  method: "POST",
  handler: handleMoniMeWebhook,
});

// Register /api/webhooks/monime alias
http.route({
  path: "/api/webhooks/monime",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }),
});

http.route({
  path: "/api/webhooks/monime",
  method: "POST",
  handler: handleMoniMeWebhook,
});

export default http;


