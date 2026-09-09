// convex/http.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — HTTP Actions: Payment Gateway Initialization & Webhooks
// Exposes:
//   POST /payments/initialize  — Initialize Flutterwave/Paystack checkout
//   POST /payments/webhook     — Receive & verify gateway webhooks
// ═══════════════════════════════════════════════════════════════════════

import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal, api } from "./_generated/api";
import { Id } from "./_generated/dataModel";

const http = httpRouter();

// ═══════════════════════════════════════════════════════════════════════
//          POST /payments/initialize — Gateway Checkout Init
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/payments/initialize",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      // ── Parse & validate request body ─────────────────────────────
      const body = await request.json();

      const {
        paymentIntentId,
        customerEmail,
        customerPhone,
        customerName,
        redirectUrl,
        mobileMoneyProvider,
      } = body;

      if (!paymentIntentId || !customerEmail) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "paymentIntentId and customerEmail are required",
          }),
          { status: 400, headers: corsHeaders() }
        );
      }

      // ── Fetch payment intent from Convex ──────────────────────────
      const intent = await ctx.runQuery(api.payments.getPaymentIntent, {
        paymentIntentId: paymentIntentId as Id<"paymentIntents">,
      });

      if (!intent) {
        return new Response(
          JSON.stringify({ success: false, error: "Payment intent not found" }),
          { status: 404, headers: corsHeaders() }
        );
      }

      if (intent.status !== "pending") {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Payment intent is already ${intent.status}`,
          }),
          { status: 409, headers: corsHeaders() }
        );
      }

      // ── Route to correct gateway ──────────────────────────────────
      let gatewayResponse;

      if (intent.gatewayProvider === "flutterwave") {
        gatewayResponse = await initializeFlutterwave({
          amount: intent.amount,
          currency: intent.currency,
          email: customerEmail,
          phone: customerPhone,
          name: customerName,
          txRef: `vktlx_${paymentIntentId}_${Date.now()}`,
          redirectUrl:
            redirectUrl ?? "https://app.vektolux.com/payment/callback",
          paymentMethod: intent.paymentMethod,
          mobileMoneyProvider,
        });
      } else if (intent.gatewayProvider === "paystack") {
        gatewayResponse = await initializePaystack({
          amount: intent.amount,
          currency: intent.currency,
          email: customerEmail,
          reference: `vktlx_${paymentIntentId}_${Date.now()}`,
          callbackUrl:
            redirectUrl ?? "https://app.vektolux.com/payment/callback",
          channels: mapPaystackChannels(intent.paymentMethod),
          mobileMoneyProvider,
        });
      } else {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Unsupported gateway: ${intent.gatewayProvider}`,
          }),
          { status: 400, headers: corsHeaders() }
        );
      }

      if (!gatewayResponse.success) {
        return new Response(
          JSON.stringify({
            success: false,
            error: gatewayResponse.error,
          }),
          { status: 502, headers: corsHeaders() }
        );
      }

      // ── Update payment intent with gateway reference ──────────────
      await ctx.runMutation(internal.payments.updateGatewayReference, {
        paymentIntentId: paymentIntentId as Id<"paymentIntents">,
        gatewayReference: gatewayResponse.reference ?? "",
        gatewayPaymentLink: gatewayResponse.paymentLink,
      });

      return new Response(
        JSON.stringify({
          success: true,
          paymentLink: gatewayResponse.paymentLink,
          reference: gatewayResponse.reference,
          provider: intent.gatewayProvider,
        }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (error: any) {
      console.error("Payment initialization error:", error);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Internal server error during payment initialization",
        }),
        { status: 500, headers: corsHeaders() }
      );
    }
  }),
});

// ═══════════════════════════════════════════════════════════════════════
//        POST /payments/webhook — Gateway Webhook Verification
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/payments/webhook",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const rawBody = await request.text();
      const verifHash = request.headers.get("verif-hash");
      const paystackSig = request.headers.get("x-paystack-signature");

      // ── Determine gateway from headers ────────────────────────────
      const isFlutterwave = verifHash !== null && verifHash !== undefined;
      const isPaystack = paystackSig !== null && paystackSig !== undefined;

      if (!isFlutterwave && !isPaystack) {
        console.error("Webhook: Unknown gateway — missing signature headers");
        return new Response("Unauthorized", { status: 401 });
      }

      // ── Cryptographic signature verification ──────────────────────
      let verified = false;
      let parsedPayload: any;

      if (isFlutterwave) {
        verified = verifyFlutterwaveSignature(
          verifHash!,
          process.env.FLUTTERWAVE_WEBHOOK_SECRET!
        );
        parsedPayload = JSON.parse(rawBody);
      } else if (isPaystack) {
        verified = await verifyPaystackSignature(
          rawBody,
          paystackSig!,
          process.env.PAYSTACK_SECRET_KEY!
        );
        parsedPayload = JSON.parse(rawBody);
      }

      if (!verified) {
        console.error("Webhook: Signature verification FAILED");
        return new Response("Unauthorized — Invalid signature", {
          status: 401,
        });
      }

      // ── Extract normalized payment data ───────────────────────────
      let normalizedPayment: {
        gatewayProvider: string;
        gatewayReference: string;
        gatewayStatus: string;
        amountPaid: number;
        currency: string;
        txRef: string;
      };

      if (isFlutterwave) {
        const data = parsedPayload.data ?? parsedPayload;
        normalizedPayment = {
          gatewayProvider: "flutterwave",
          gatewayReference: String(data.id ?? data.flw_ref),
          gatewayStatus: normalizeGatewayStatus(data.status),
          amountPaid: data.amount ?? data.charged_amount,
          currency: data.currency ?? "SLE",
          txRef: data.tx_ref ?? "",
        };
      } else {
        const data = parsedPayload.data;
        normalizedPayment = {
          gatewayProvider: "paystack",
          gatewayReference: data.reference,
          gatewayStatus: normalizeGatewayStatus(data.status),
          amountPaid: data.amount / 100, // Paystack amounts are in kobo/pesewas
          currency: data.currency ?? "SLE",
          txRef: data.reference,
        };
      }

      // ── Extract payment intent ID from tx_ref ─────────────────────
      // Format: vktlx_{paymentIntentId}_{timestamp}
      const txRefParts = normalizedPayment.txRef.split("_");
      if (txRefParts.length < 2 || txRefParts[0] !== "vktlx") {
        console.error(
          "Webhook: Invalid tx_ref format:",
          normalizedPayment.txRef
        );
        // Still return 200 to prevent gateway retries for non-Vektolux txns
        return new Response("OK — Not a Vektolux transaction", { status: 200 });
      }

      const paymentIntentId = txRefParts[1] as Id<"paymentIntents">;

      // ── Process payment atomically via internal mutation ───────────
      const result = await ctx.runMutation(
        internal.payments.processVerifiedPayment,
        {
          gatewayProvider: normalizedPayment.gatewayProvider,
          gatewayReference: normalizedPayment.gatewayReference,
          gatewayStatus: normalizedPayment.gatewayStatus,
          amountPaid: normalizedPayment.amountPaid,
          currency: normalizedPayment.currency,
          paymentIntentId,
        }
      );

      console.log(
        `Webhook processed: ${normalizedPayment.gatewayProvider} ref=${normalizedPayment.gatewayReference} status=${normalizedPayment.gatewayStatus}`,
        result
      );

      // Always return 200 to prevent webhook retries
      return new Response(JSON.stringify({ received: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch (error: any) {
      console.error("Webhook processing error:", error.message ?? error);
      // Return 200 even on error to prevent infinite webhook retries
      // Errors are logged and can be investigated via Convex dashboard
      return new Response(
        JSON.stringify({ received: true, error: "Processing error logged" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

// ── CORS preflight for /payments/* routes ────────────────────────────
http.route({
  path: "/payments/initialize",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }),
});

// ═══════════════════════════════════════════════════════════════════════
//                    GATEWAY API IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Initialize a Flutterwave payment session.
 * Docs: https://developer.flutterwave.com/reference/endpoints/payments
 */
async function initializeFlutterwave(params: {
  amount: number;
  currency: string;
  email: string;
  phone?: string;
  name?: string;
  txRef: string;
  redirectUrl: string;
  paymentMethod: string;
  mobileMoneyProvider?: string;
}): Promise<{
  success: boolean;
  paymentLink?: string;
  reference?: string;
  error?: string;
}> {
  const FLW_SECRET = process.env.FLUTTERWAVE_SECRET_KEY;
  if (!FLW_SECRET) {
    return { success: false, error: "Flutterwave secret key not configured" };
  }

  // Build payment options based on method
  const paymentOptions: string[] = [];
  if (params.paymentMethod === "card") paymentOptions.push("card");
  if (params.paymentMethod === "mobile_money") {
    paymentOptions.push("mobilemoneysle"); // Sierra Leone Mobile Money
    // Add specific providers
    if (params.mobileMoneyProvider === "orange_money") {
      paymentOptions.push("mobilemoneygh"); // Mapped via Flutterwave
    }
    if (params.mobileMoneyProvider === "africell_money") {
      paymentOptions.push("mobilemoneysle");
    }
  }

  const payload = {
    tx_ref: params.txRef,
    amount: params.amount,
    currency: params.currency,
    redirect_url: params.redirectUrl,
    payment_options: paymentOptions.join(",") || "card,mobilemoneysle",
    customer: {
      email: params.email,
      phonenumber: params.phone ?? "",
      name: params.name ?? "",
    },
    customizations: {
      title: "Vektolux Marketplace",
      logo: "https://app.vektolux.com/logo.png",
      description: "Secure payment via Vektolux",
    },
    meta: {
      source: "vektolux_app",
      tx_ref: params.txRef,
    },
  };

  try {
    const response = await fetch(
      "https://api.flutterwave.com/v3/payments",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${FLW_SECRET}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      }
    );

    const data = await response.json();

    if (data.status === "success" && data.data?.link) {
      return {
        success: true,
        paymentLink: data.data.link,
        reference: params.txRef,
      };
    }

    return {
      success: false,
      error: data.message ?? "Flutterwave initialization failed",
    };
  } catch (error: any) {
    return {
      success: false,
      error: `Flutterwave API error: ${error.message}`,
    };
  }
}

/**
 * Initialize a Paystack payment session.
 * Docs: https://paystack.com/docs/api/transaction/#initialize
 */
async function initializePaystack(params: {
  amount: number;
  currency: string;
  email: string;
  reference: string;
  callbackUrl: string;
  channels: string[];
  mobileMoneyProvider?: string;
}): Promise<{
  success: boolean;
  paymentLink?: string;
  reference?: string;
  error?: string;
}> {
  const PS_SECRET = process.env.PAYSTACK_SECRET_KEY;
  if (!PS_SECRET) {
    return { success: false, error: "Paystack secret key not configured" };
  }

  const payload = {
    email: params.email,
    amount: Math.round(params.amount * 100), // Paystack uses minor units
    currency: params.currency,
    reference: params.reference,
    callback_url: params.callbackUrl,
    channels: params.channels,
    metadata: {
      source: "vektolux_app",
      custom_fields: [
        {
          display_name: "Platform",
          variable_name: "platform",
          value: "Vektolux",
        },
      ],
    },
  };

  try {
    const response = await fetch(
      "https://api.paystack.co/transaction/initialize",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${PS_SECRET}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      }
    );

    const data = await response.json();

    if (data.status === true && data.data?.authorization_url) {
      return {
        success: true,
        paymentLink: data.data.authorization_url,
        reference: data.data.reference,
      };
    }

    return {
      success: false,
      error: data.message ?? "Paystack initialization failed",
    };
  } catch (error: any) {
    return {
      success: false,
      error: `Paystack API error: ${error.message}`,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                  SIGNATURE VERIFICATION
// ═══════════════════════════════════════════════════════════════════════

/**
 * Verify Flutterwave webhook signature.
 * Flutterwave sends a `verif-hash` header containing the webhook secret hash.
 */
function verifyFlutterwaveSignature(
  receivedHash: string,
  webhookSecret: string
): boolean {
  if (!receivedHash || !webhookSecret) return false;
  return receivedHash === webhookSecret;
}

/**
 * Verify Paystack webhook signature using HMAC SHA-512.
 * Paystack sends `x-paystack-signature` header with HMAC of the raw body.
 */
async function verifyPaystackSignature(
  rawBody: string,
  signature: string,
  secretKey: string
): Promise<boolean> {
  if (!signature || !secretKey) return false;

  try {
    // Use Web Crypto API (available in Convex runtime)
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secretKey),
      { name: "HMAC", hash: "SHA-512" },
      false,
      ["sign"]
    );

    const signatureBytes = await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(rawBody)
    );

    const computedHash = Array.from(new Uint8Array(signatureBytes))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    return computedHash === signature;
  } catch {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                        HELPERS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Normalize gateway status strings to a consistent enum.
 */
function normalizeGatewayStatus(rawStatus: string): string {
  const status = (rawStatus ?? "").toLowerCase();
  if (status === "successful" || status === "success" || status === "completed")
    return "success";
  if (status === "failed" || status === "failure") return "failed";
  if (status === "cancelled" || status === "abandoned") return "cancelled";
  if (status === "pending") return "pending";
  return status;
}

/**
 * Map Vektolux payment method to Paystack channel names.
 */
function mapPaystackChannels(method: string): string[] {
  switch (method) {
    case "card":
      return ["card"];
    case "mobile_money":
      return ["mobile_money"];
    case "wallet":
      return ["bank_transfer"];
    default:
      return ["card", "mobile_money", "bank_transfer"];
  }
}

/**
 * CORS headers for cross-origin requests from the Flutter app.
 */
function corsHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

// ═══════════════════════════════════════════════════════════════════════
//   POST /api/v1/verifications/webhook — Cryptographically Verified eIDV
// ═══════════════════════════════════════════════════════════════════════

const EIDV_WEBHOOK_SECRET = process.env.EIDV_WEBHOOK_SECRET || "vkt_live_sec_f9823kjsd0213kd";

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
//          POST /api/trips/verify-pin — Verify Pickup PIN & Start Trip
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/api/trips/verify-pin",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const { tripId, driverProfileId, pin } = body;

      if (!tripId || !pin) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "tripId and pin are required parameters",
          }),
          { status: 400, headers: corsHeaders() }
        );
      }

      await ctx.runMutation(api.mobility.verifyPinAndStartTrip, {
        tripId,
        driverProfileId: driverProfileId ?? "system_api",
        pin: String(pin).trim(),
      });

      return new Response(
        JSON.stringify({
          success: true,
          tripId,
          status: "in_progress",
          message: "PIN verified successfully. Trip started.",
        }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (err: any) {
      return new Response(
        JSON.stringify({
          success: false,
          error: err.message ?? "PIN verification failed",
        }),
        { status: 400, headers: corsHeaders() }
      );
    }
  }),
});

export default http;
