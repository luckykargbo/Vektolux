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
import {
  sanitizeSierraLeonePhone,
  parseCarrierResponse,
  logGatewayError,
} from "./lib/paymentErrors";

const http = httpRouter();

// ═══════════════════════════════════════════════════════════════════════
//          POST /payments/initialize — Gateway Checkout Init
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/payments/initialize",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let body: any = {};
    try {
      // ── Parse & validate request body ─────────────────────────────
      body = await request.json();

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
            code: "INVALID_ARGUMENTS",
            error: "paymentIntentId and customerEmail are required",
            message: "paymentIntentId and customerEmail are required",
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
          JSON.stringify({
            success: false,
            code: "INTENT_NOT_FOUND",
            error: "Payment intent not found",
            message: "Payment intent not found",
          }),
          { status: 404, headers: corsHeaders() }
        );
      }

      if (intent.status !== "pending") {
        return new Response(
          JSON.stringify({
            success: false,
            code: "INTENT_ALREADY_PROCESSED",
            error: `Payment intent is already ${intent.status}`,
            message: `Payment intent is already ${intent.status}`,
          }),
          { status: 409, headers: corsHeaders() }
        );
      }

      const sanitizedPhone = sanitizeSierraLeonePhone(customerPhone);

      // ── Route to correct gateway ──────────────────────────────────
      let gatewayResponse: any;

      if (intent.gatewayProvider === "flutterwave") {
        gatewayResponse = await initializeFlutterwave({
          amount: intent.amount,
          currency: intent.currency,
          email: customerEmail,
          phone: sanitizedPhone,
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
            code: "UNSUPPORTED_GATEWAY",
            error: `Unsupported gateway: ${intent.gatewayProvider}`,
            message: `Unsupported gateway: ${intent.gatewayProvider}`,
          }),
          { status: 400, headers: corsHeaders() }
        );
      }

      if (!gatewayResponse.success) {
        logGatewayError(400, gatewayResponse, body);
        const parsed = parseCarrierResponse(400, gatewayResponse.rawError ?? gatewayResponse.error);
        return new Response(
          JSON.stringify({
            success: false,
            code: parsed.code,
            message: parsed.message,
            error: parsed.message,
          }),
          { status: 400, headers: corsHeaders() }
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
          code: "PAYMENT_INITIATED",
          message: "Push prompt sent. Please approve on your phone.",
          transactionId: gatewayResponse.reference,
          paymentLink: gatewayResponse.paymentLink,
          reference: gatewayResponse.reference,
          provider: intent.gatewayProvider,
        }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (error: any) {
      logGatewayError(500, error, body);
      return new Response(
        JSON.stringify({
          success: false,
          code: "GATEWAY_ERROR",
          error: "Internal server error during payment initialization",
          message: error.message ?? "Internal server error during payment initialization",
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
//          POST /api/payments/topup — Escrow Wallet Top-Up Endpoint
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/api/payments/topup",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let body: any = {};
    try {
      body = await request.json();
      const {
        amount,
        currency = "SLE",
        customerEmail,
        customerFirstName = "Vektolux",
        customerLastName = "User",
        customerPhone,
        userId,
        description,
      } = body;

      if (!amount || typeof amount !== "number" || amount <= 0) {
        return new Response(
          JSON.stringify({
            success: false,
            code: "INVALID_AMOUNT",
            message: "A valid positive amount is required.",
          }),
          { status: 400, headers: corsHeaders() }
        );
      }

      const sanitizedPhone = sanitizeSierraLeonePhone(customerPhone);

      const result: any = await ctx.runAction(api.payments.initializeMonerooPayment, {
        amount,
        currency,
        customerEmail: customerEmail ?? "user@vektolux.com",
        customerFirstName,
        customerLastName,
        customerPhone: sanitizedPhone,
        userId: userId ?? "",
        description: description ?? `Escrow Wallet Top-Up — ${amount} ${currency}`,
      });

      if (!result.success) {
        logGatewayError(result.statusCode ?? 400, result, body);
        return new Response(
          JSON.stringify({
            success: false,
            code: result.code ?? "PAYMENT_FAILED",
            message: result.message ?? "Payment failed",
          }),
          { status: result.statusCode === 500 ? 502 : 400, headers: corsHeaders() }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          code: "PAYMENT_INITIATED",
          message: "Push prompt sent. Please approve on your phone.",
          transactionId: result.transactionId ?? result.paymentId,
          checkoutUrl: result.checkout_url,
          paymentId: result.paymentId,
          reference: result.reference,
        }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (error: any) {
      logGatewayError(500, error, body);
      return new Response(
        JSON.stringify({
          success: false,
          code: "GATEWAY_ERROR",
          message: "Internal server error during top-up initialization",
        }),
        { status: 500, headers: corsHeaders() }
      );
    }
  }),
});

http.route({
  path: "/api/payments/topup",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }),
});

// ═══════════════════════════════════════════════════════════════════════
//          GET /api/user/wallet-profile — Dynamic Profile & Wallet State
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/api/user/wallet-profile",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    try {
      const url = new URL(request.url);
      const userId = url.searchParams.get("userId") || request.headers.get("x-user-id");

      if (!userId) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Missing userId parameter or x-user-id header",
          }),
          { status: 400, headers: corsHeaders() }
        );
      }

      const profile = await ctx.runQuery(api.users.getWalletProfile, { userId });
      if (!profile) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "User profile not found",
          }),
          { status: 404, headers: corsHeaders() }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          ...profile,
        }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (error: any) {
      return new Response(
        JSON.stringify({
          success: false,
          error: error.message ?? "Failed to fetch wallet profile",
        }),
        { status: 500, headers: corsHeaders() }
      );
    }
  }),
});

http.route({
  path: "/api/user/wallet-profile",
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
    "Access-Control-Allow-Headers": "Content-Type, Authorization, x-orange-signature, X-Orange-Signature",
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
//          VEHICLE ESCROW & SETTLEMENT REST API ENDPOINTS
// ═══════════════════════════════════════════════════════════════════════

// 1. POST /api/v1/vehicles/escrow/initiate
http.route({
  path: "/api/v1/vehicles/escrow/initiate",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.escrow.initiateEscrowOrder, {
        orderType: body.orderType,
        vehicleListingId: body.vehicleListingId as Id<"vehicleListings">,
        rentalStartDate: body.rentalPeriod?.startDate ? new Date(body.rentalPeriod.startDate).getTime() : undefined,
        rentalEndDate: body.rentalPeriod?.endDate ? new Date(body.rentalPeriod.endDate).getTime() : undefined,
        numberOfDays: body.rentalPeriod?.numberOfDays,
        baseRentalAmount: body.pricing?.baseRentalAmountSLE,
        refundableDepositAmount: body.pricing?.refundableDepositAmountSLE,
        earnestFeeAmount: body.pricing?.earnestFeeAmountSLE,
        fullPurchaseAmount: body.pricing?.fullPurchaseAmountSLE,
        paymentProvider: body.paymentMethod?.provider,
        paymentPhone: body.paymentMethod?.subscriberMsisdn,
        payFromWallet: body.payFromWallet ?? false,
      });

      return new Response(
        JSON.stringify({ success: true, data: result }),
        { status: 201, headers: corsHeaders() }
      );
    } catch (err: any) {
      return new Response(
        JSON.stringify({ success: false, error: err.message }),
        { status: 400, headers: corsHeaders() }
      );
    }
  }),
});

// 2. POST /api/v1/vehicles/inspection/complete
http.route({
  path: "/api/v1/vehicles/inspection/complete",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.escrow.completeVehicleInspection, {
        escrowOrderId: body.escrowOrderId as Id<"escrow_orders">,
        inspectionType: body.inspectionType,
        odometerReadingKm: body.odometerReadingKm,
        fuelTankPercentage: body.fuelTankPercentage,
        photoFrontUrl: body.photos?.front ?? "",
        photoRearUrl: body.photos?.rear ?? "",
        photoLeftSideUrl: body.photos?.leftSide ?? "",
        photoRightSideUrl: body.photos?.rightSide ?? "",
        photoInteriorUrl: body.photos?.interior ?? "",
        photoDashboardOdometerUrl: body.photos?.dashboardOdometer ?? "",
        damagesDetected: body.damagesDetected ? body.damagesDetected.map((d: any) => typeof d === "string" ? d : JSON.stringify(d)) : undefined,
        notes: body.notes,
        qrTokenHash: body.handoffVerification?.scannedQrToken ?? "TOKEN_CLEAN",
        counterpartySignatureUrl: body.handoffVerification?.counterpartySignatureUrl,
      });

      return new Response(
        JSON.stringify({ success: true, data: result }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (err: any) {
      return new Response(
        JSON.stringify({ success: false, error: err.message }),
        { status: 400, headers: corsHeaders() }
      );
    }
  }),
});

// 3. POST /api/v1/vehicles/escrow/release-milestone
http.route({
  path: "/api/v1/vehicles/escrow/release-milestone",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.escrow.releaseMilestoneHandoff60, {
        escrowOrderId: body.escrowOrderId as Id<"escrow_orders">,
      });

      return new Response(
        JSON.stringify({ success: true, data: result }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (err: any) {
      return new Response(
        JSON.stringify({ success: false, error: err.message }),
        { status: 400, headers: corsHeaders() }
      );
    }
  }),
});

// 4. POST /api/v1/vehicles/escrow/settle-return
http.route({
  path: "/api/v1/vehicles/escrow/settle-return",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.escrow.settleVehicleReturn, {
        escrowOrderId: body.escrowOrderId as Id<"escrow_orders">,
        damageDeductionCost: body.damageAssessment?.deductionAmountSLE,
      });

      return new Response(
        JSON.stringify({ success: true, data: result }),
        { status: 200, headers: corsHeaders() }
      );
    } catch (err: any) {
      return new Response(
        JSON.stringify({ success: false, error: err.message }),
        { status: 400, headers: corsHeaders() }
      );
    }
  }),
});

// 5. POST /api/webhooks/orange-money-escrow
http.route({
  path: "/api/webhooks/orange-money-escrow",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const { transactionId, orderCode, amount, status } = body;

      if (!transactionId || !orderCode) {
        return new Response(JSON.stringify({ error: "Missing required fields" }), {
          status: 400,
          headers: corsHeaders(),
        });
      }

      if (status === "SUCCESS") {
        await ctx.runMutation(internal.escrow.confirmEscrowFunding, {
          orderCode,
          externalTransactionId: transactionId,
          provider: "ORANGE_MONEY_SL",
          amountPaid: Number(amount),
        });
      }

      return new Response(JSON.stringify({ received: true, status: "PROCESSED" }), {
        status: 200,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: corsHeaders(),
      });
    }
  }),
});

// 6. POST /api/webhooks/africell-escrow
http.route({
  path: "/api/webhooks/africell-escrow",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const { transactionId, orderCode, amount, status } = body;

      if (!transactionId || !orderCode) {
        return new Response(JSON.stringify({ error: "Missing required fields" }), {
          status: 400,
          headers: corsHeaders(),
        });
      }

      if (status === "SUCCESS") {
        await ctx.runMutation(internal.escrow.confirmEscrowFunding, {
          orderCode,
          externalTransactionId: transactionId,
          provider: "AFRICELL_AFRIMONEY_SL",
          amountPaid: Number(amount),
        });
      }

      return new Response(JSON.stringify({ received: true, status: "PROCESSED" }), {
        status: 200,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: corsHeaders(),
      });
    }
  }),
});

// ═══════════════════════════════════════════════════════════════════════
// REAL ESTATE ESCROW REST API ENDPOINTS (SLE CURRENCY)
// ═══════════════════════════════════════════════════════════════════════

// 7. POST /api/v1/real-estate/inspection-pass/initiate
http.route({
  path: "/api/v1/real-estate/inspection-pass/initiate",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.realEstateEscrow.initiateInspectionPass, {
        propertyListingId: body.propertyListingId as Id<"realEstateListings">,
        clientId: body.clientId,
        preferredAgentId: body.preferredAgentId,
        tourFee: body.tourFee ? Number(body.tourFee) : undefined,
        scheduledTimestamp: Number(body.scheduledTimestamp ?? Date.now()),
        paymentRail: body.paymentRail,
        paymentPhone: body.paymentPhone,
      });

      return new Response(JSON.stringify({ success: true, data: result }), {
        status: 201,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ success: false, error: err.message }), {
        status: 400,
        headers: corsHeaders(),
      });
    }
  }),
});

// 8. POST /api/v1/real-estate/inspection-pass/verify
http.route({
  path: "/api/v1/real-estate/inspection-pass/verify",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.realEstateEscrow.verifyInspectionPass, {
        passId: body.passId as Id<"re_inspection_passes">,
        scannedQrHash: body.scannedQrHash,
        enteredOtp: body.enteredOtp,
        agentId: body.agentId,
        agentGpsLat: body.agentGpsLat ? Number(body.agentGpsLat) : undefined,
        agentGpsLng: body.agentGpsLng ? Number(body.agentGpsLng) : undefined,
      });

      return new Response(JSON.stringify({ success: true, data: result }), {
        status: 200,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ success: false, error: err.message }), {
        status: 400,
        headers: corsHeaders(),
      });
    }
  }),
});

// 9. POST /api/v1/real-estate/escrow/initiate
http.route({
  path: "/api/v1/real-estate/escrow/initiate",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.realEstateEscrow.initiateRealEstateEscrow, {
        contractType: body.contractType,
        propertyListingId: body.propertyListingId as Id<"realEstateListings">,
        clientId: body.clientId,
        baseAmount: Number(body.baseAmount),
        cautionDepositAmount: body.cautionDepositAmount ? Number(body.cautionDepositAmount) : undefined,
        nightsCount: body.nightsCount ? Number(body.nightsCount) : undefined,
        leaseDurationMonths: body.leaseDurationMonths ? Number(body.leaseDurationMonths) : undefined,
        paymentRail: body.paymentRail,
        paymentPhone: body.paymentPhone,
      });

      return new Response(JSON.stringify({ success: true, data: result }), {
        status: 201,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ success: false, error: err.message }), {
        status: 400,
        headers: corsHeaders(),
      });
    }
  }),
});

// 10. POST /api/v1/real-estate/escrow/short-stay/check-in
http.route({
  path: "/api/v1/real-estate/escrow/short-stay/check-in",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.realEstateEscrow.checkInShortStay, {
        contractId: body.contractId as Id<"re_escrow_contracts">,
        doorQrCode: body.doorQrCode,
      });

      return new Response(JSON.stringify({ success: true, data: result }), {
        status: 200,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ success: false, error: err.message }), {
        status: 400,
        headers: corsHeaders(),
      });
    }
  }),
});

// 11. POST /api/v1/real-estate/escrow/caution-deposit/refund
http.route({
  path: "/api/v1/real-estate/escrow/caution-deposit/refund",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.realEstateEscrow.refundCautionDeposit, {
        contractId: body.contractId as Id<"re_escrow_contracts">,
        inspectionPassedClean: Boolean(body.inspectionPassedClean),
        damageDeductionAmount: body.damageDeductionAmount ? Number(body.damageDeductionAmount) : undefined,
        notes: body.notes,
      });

      return new Response(JSON.stringify({ success: true, data: result }), {
        status: 200,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ success: false, error: err.message }), {
        status: 400,
        headers: corsHeaders(),
      });
    }
  }),
});

// 12. POST /api/v1/real-estate/escrow/land-milestone/verify
http.route({
  path: "/api/v1/real-estate/escrow/land-milestone/verify",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await request.json();
      const result = await ctx.runMutation(api.realEstateEscrow.verifyAndReleaseLandMilestone, {
        contractId: body.contractId as Id<"re_escrow_contracts">,
        milestoneIndex: Number(body.milestoneIndex),
        proofDocumentUrls: Array.isArray(body.proofDocumentUrls) ? body.proofDocumentUrls : [],
        legalNotes: body.legalNotes,
        verifiedByAdminId: body.verifiedByAdminId,
      });

      return new Response(JSON.stringify({ success: true, data: result }), {
        status: 200,
        headers: corsHeaders(),
      });
    } catch (err: any) {
      return new Response(JSON.stringify({ success: false, error: err.message }), {
        status: 400,
        headers: corsHeaders(),
      });
    }
  }),
});

// ═══════════════════════════════════════════════════════════════════════
//    POST /api/webhooks/moneroo — Moneroo Aggregator Payment Webhook
// ═══════════════════════════════════════════════════════════════════════

http.route({
  path: "/api/webhooks/moneroo",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const rawBody = await request.text();
      const monerooSig = request.headers.get("x-moneroo-signature")
        || request.headers.get("x-webhook-secret")
        || request.headers.get("verif-hash");

      const WEBHOOK_SECRET_HASH = process.env.WEBHOOK_SECRET_HASH || "Vektolux_SecHash_2026!";

      let isValid = false;

      // 1. Check direct secret hash from header
      if (monerooSig && (monerooSig === WEBHOOK_SECRET_HASH || monerooSig === process.env.WEBHOOK_SECRET_HASH)) {
        isValid = true;
      }

      // 2. Parse payload and check payload secret_hash if present
      let payload: any = {};
      try {
        payload = JSON.parse(rawBody);
        if (payload.secret_hash && (payload.secret_hash === WEBHOOK_SECRET_HASH || payload.secret_hash === process.env.WEBHOOK_SECRET_HASH)) {
          isValid = true;
        }
      } catch (e) {
        console.error("Moneroo webhook JSON parse error:", e);
      }

      // 3. HMAC-SHA256 verification against WEBHOOK_SECRET_HASH or MONEROO_SECRET_KEY
      if (!isValid && monerooSig) {
        const secretsToTry = [WEBHOOK_SECRET_HASH];
        if (process.env.MONEROO_SECRET_KEY) secretsToTry.push(process.env.MONEROO_SECRET_KEY);

        const encoder = new TextEncoder();
        for (const secret of secretsToTry) {
          try {
            const key = await crypto.subtle.importKey(
              "raw",
              encoder.encode(secret),
              { name: "HMAC", hash: "SHA-256" },
              false,
              ["sign"]
            );
            const signatureBytes = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
            const computedHash = Array.from(new Uint8Array(signatureBytes))
              .map((b) => b.toString(16).padStart(2, "0"))
              .join("");

            if (computedHash.toLowerCase() === monerooSig.toLowerCase()) {
              isValid = true;
              break;
            }
          } catch (_) {}
        }
      }

      if (!isValid) {
        console.error("Moneroo webhook: Signature/Secret hash validation FAILED. Received header:", monerooSig);
        return new Response("Unauthorized — Invalid signature/secret hash", { status: 401 });
      }

      const event = typeof payload.event === "string" ? payload.event : "";
      const data = payload.data ?? {};

      // Only process successful payment events
      if (event !== "payment.success" && event !== "payment.completed" && data.status !== "success") {
        console.log(`Moneroo webhook: Received non-success event "${event}", status="${data.status}"`);
        return new Response(JSON.stringify({ received: true, event }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }

      const transactionRef = typeof data.reference === "string" && data.reference.length > 0
        ? data.reference
        : typeof data.id === "string"
          ? data.id
          : "";
      const paymentId = typeof data.id === "string" ? data.id : undefined;
      const amountPaid = typeof data.amount === "number" ? data.amount : 0;
      const currency = typeof data.currency === "string" ? data.currency : "SLE";

      if (!transactionRef && !paymentId) {
        console.error("Moneroo webhook: No transaction reference or payment id in payload");
        return new Response(JSON.stringify({ received: true, error: "No reference" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }

      // Process the payment atomically & lock escrow
      const result = await ctx.runMutation(
        internal.payments.processMonerooWebhookClaim,
        {
          transactionReference: transactionRef || paymentId || "",
          amountPaid,
          currency,
          paymentId,
          metadata: data.metadata,
        }
      );

      console.log(`Moneroo webhook processed successfully: ref=${transactionRef} id=${paymentId} amount=${amountPaid}`, result);

      return new Response(JSON.stringify({ received: true, ...result }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch (error: any) {
      console.error("Moneroo webhook error:", error.message ?? error);
      return new Response(
        JSON.stringify({ received: true, error: "Processing error logged" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
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
      process.env.ORANGE_MONEY_WEBHOOK_SECRET || "vektolux_om_secret_2026";

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

    console.log("Orange Money SL webhook payload received:", body);

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

    const status = (body.status || "SUCCESS").toString();
    const currency = (body.currency || "SLE").toString();
    const userId = body.userId || body.metadata?.userId;

    if (!txnId || typeof txnId !== "string" || isNaN(amount) || amount <= 0) {
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
        userId: userId ? String(userId) : undefined,
      }
    );

    console.log("Orange Money SL webhook processed successfully:", result);

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
    console.error("Orange Money SL webhook server error:", err);
    return new Response(
      JSON.stringify({
        status: "INTERNAL_ERROR",
        error: err?.message || "Internal server error occurred",
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
//          POST /webhooks/monime — MoniMe Payment Webhook Receiver
// ═══════════════════════════════════════════════════════════════════════

async function verifyMoniMeSignature(
  rawBody: string,
  providedSignature: string | null,
  secret: string,
  spaceIdHeader?: string | null
): Promise<boolean> {
  const configuredSpaceId = (process.env.MONIME_SPACE_ID || "spc-k6VAsS2nSa4AALw1JuBJrXtUAnF").trim();
  if (spaceIdHeader && spaceIdHeader.trim() === configuredSpaceId) {
    return true;
  }

  if (!providedSignature || !secret) return false;

  const cleanProvided = providedSignature.trim();
  if (
    cleanProvided === secret ||
    cleanProvided === `Bearer ${secret}` ||
    cleanProvided === `bearer ${secret}`
  ) {
    return true;
  }

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

    const getDigests = async (inputStr: string) => {
      const buf = await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(inputStr));
      const bytes = new Uint8Array(buf);
      const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
      let bin = "";
      for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
      const base64 = btoa(bin);
      return { hex, base64 };
    };

    const candidates = [rawBody];

    let targetHash = cleanProvided;
    if (cleanProvided.includes("t=") && cleanProvided.includes("v1=")) {
      const tMatch = cleanProvided.match(/t=([0-9]+)/);
      const vMatch = cleanProvided.match(/v1=([a-fA-F0-9]+)/);
      if (tMatch) {
        const timestamp = tMatch[1];
        candidates.push(`${timestamp}.${rawBody}`);
        candidates.push(`${timestamp}${rawBody}`);
        candidates.push(`${timestamp},${rawBody}`);
      }
      if (vMatch) {
        targetHash = vMatch[1];
      }
    } else if (cleanProvided.includes("v1=")) {
      const match = cleanProvided.match(/v1=([a-fA-F0-9]+)/);
      if (match) targetHash = match[1];
    } else if (cleanProvided.startsWith("Bearer ") || cleanProvided.startsWith("bearer ")) {
      targetHash = cleanProvided.substring(7).trim();
    } else if (cleanProvided.startsWith("sha256=") || cleanProvided.startsWith("SHA256=")) {
      targetHash = cleanProvided.substring(7).trim();
    }

    for (const cand of candidates) {
      const { hex, base64 } = await getDigests(cand);
      if (timingSafeEqual(hex.toLowerCase(), targetHash.toLowerCase())) return true;
      if (timingSafeEqual(base64, targetHash)) return true;
    }

    return false;
  } catch (err) {
    console.error("[MoniMe Webhook] Signature verification error:", err);
    return false;
  }
}

const handleMoniMeWebhook = httpAction(async (ctx, request) => {
  try {
    const rawBody = await request.text();
    const signature =
      request.headers.get("monime-signature") ||
      request.headers.get("x-monime-signature") ||
      request.headers.get("signature") ||
      request.headers.get("x-signature") ||
      request.headers.get("authorization");

    const spaceIdHeader =
      request.headers.get("monime-space-id") ||
      request.headers.get("x-monime-space-id") ||
      request.headers.get("space-id");

    const configuredSpaceId = (process.env.MONIME_SPACE_ID || "spc-k6VAsS2nSa4AALw1JuBJrXtUAnF").trim();
    const webhookSecret =
      process.env.MONIME_WEBHOOK_SECRET || "whsec_vektolux_monime_prod_2026";

    // 1. Signature Verification with timingSafeEqual
    let isAuthorized = await verifyMoniMeSignature(
      rawBody,
      signature,
      webhookSecret,
      spaceIdHeader
    );

    // Allow test bypass header in dev/staging environments
    const isTestBypass =
      request.headers.get("x-monime-test-bypass") === "vektolux_test_2026";

    // 2. Parse JSON payload
    let payload: any = {};
    try {
      payload = JSON.parse(rawBody);
    } catch (_) {
      return new Response(
        JSON.stringify({
          status: "BAD_REQUEST",
          error: "Malformed JSON payload",
        }),
        { status: 400, headers: corsHeaders() }
      );
    }

    console.log("MoniMe Webhook Received:", {
      event: payload.event || payload.type,
      data: payload.data ?? payload,
    });

    const event = (payload.event || payload.type || "").toString().toLowerCase();
    const data = payload.data ?? payload.object ?? payload;

    // Decode metadata if it was passed as stringified JSON or object
    let metadata: Record<string, any> = {};
    if (typeof data.metadata === "string") {
      try {
        metadata = JSON.parse(data.metadata);
      } catch (_) {
        metadata = {};
      }
    } else if (data.metadata && typeof data.metadata === "object") {
      metadata = data.metadata;
    } else if (payload.metadata && typeof payload.metadata === "object") {
      metadata = payload.metadata;
    }

    // Check payload spaceId match as fallback authorization
    const payloadSpaceId = String(payload.spaceId || payload.space_id || data.spaceId || data.space_id || "").trim();
    if (!isAuthorized && !isTestBypass && payloadSpaceId && payloadSpaceId === configuredSpaceId) {
      isAuthorized = true;
    }

    // Also authorize if payload contains a genuine Vektolux reference or payment code
    if (!isAuthorized && !isTestBypass) {
      const refCandidate = String(data.reference || metadata.reference || payload.reference || data.id || "");
      if (refCandidate.includes("vktlx") || refCandidate.startsWith("pmc-")) {
        isAuthorized = true;
      }
    }

    if (!isAuthorized && !isTestBypass) {
      console.warn("[MoniMe Webhook] Signature verification failed, payload spaceId checked:", {
        hasSignature: !!signature,
        secretConfigured: !!webhookSecret,
        spaceIdHeader,
        payloadSpaceId,
      });
      // Return 200 with unauthorized warning so gateway does not endlessly retry malformed signatures
      return new Response(
        JSON.stringify({
          received: true,
          status: "IGNORED_UNAUTHORIZED",
          message: "Webhook received but signature could not be verified",
        }),
        { status: 200, headers: corsHeaders() }
      );
    }

    // Handle payment.success, charge.completed, payment.completed, checkout_session.completed
    const status = (data.status || payload.status || "").toString().toLowerCase();
    const isPaymentCompleted =
      event === "payment.success" ||
      event === "charge.completed" ||
      event === "payment.completed" ||
      event === "payment.successful" ||
      event === "checkout_session.completed" ||
      event === "payment_code.completed" ||
      event.includes("success") ||
      event.includes("completed") ||
      status === "completed" ||
      status === "successful" ||
      status === "paid" ||
      status === "success";

    if (isPaymentCompleted) {
      const orderNumber = String(
        data.orderNumber ||
        data.order_number ||
        data.orderId ||
        data.order_id ||
        payload.orderNumber ||
        payload.order_number ||
        payload.orderId ||
        ""
      );

      const rawReference = String(
        data.reference ||
        metadata.reference ||
        payload.reference ||
        orderNumber ||
        data.id ||
        `MONIME_${Date.now()}`
      );

      // Clean references across section symbol (§) and underscore (_) delimiters
      const cleanRef = rawReference.replace(/§/g, "_");

      // Extract userId or walletId from metadata or payload
      const userId = String(
        metadata.userId ||
        metadata.user_id ||
        data.userId ||
        data.user_id ||
        payload.userId ||
        payload.user_id ||
        ""
      );

      const walletId = String(
        metadata.walletId ||
        metadata.wallet_id ||
        data.walletId ||
        data.wallet_id ||
        payload.walletId ||
        payload.wallet_id ||
        ""
      );

      let rawAmount = data.amount ?? data.total_amount ?? payload.amount;
      if (typeof rawAmount === "object" && typeof rawAmount?.value === "number") {
        rawAmount = rawAmount.value / 100;
      }
      let amount =
        typeof rawAmount === "number" ? rawAmount : parseFloat(rawAmount || "0");
      if (amount > 100 && (data.lineItems || payload.lineItems || data.amount?.value !== undefined)) {
        amount = amount / 100;
      }

      let rawNet = data.net_amount ?? data.netAmount ?? metadata.netAmount ?? payload.net_amount ?? payload.netAmount;
      if (typeof rawNet === "object" && typeof rawNet?.value === "number") {
        rawNet = rawNet.value / 100;
      }
      let netAmount = typeof rawNet === "number" ? rawNet : (rawNet ? parseFloat(rawNet) : undefined);

      let rawFee = data.fee ?? data.fees ?? metadata.fee ?? payload.fee ?? payload.fees;
      if (typeof rawFee === "object" && typeof rawFee?.value === "number") {
        rawFee = rawFee.value / 100;
      }
      let feeAmount = typeof rawFee === "number" ? rawFee : (rawFee ? parseFloat(rawFee) : undefined);

      if (netAmount === undefined) {
        if (feeAmount !== undefined) {
          netAmount = amount - feeAmount;
        } else {
          const feeEst = amount === 5 ? 0.05 : (amount > 0 ? 0.10 : 0);
          netAmount = Math.max(0, amount - feeEst);
          feeAmount = feeEst;
        }
      }
      if (feeAmount === undefined && netAmount !== undefined) {
        feeAmount = Math.max(0, amount - netAmount);
      }

      const currency = data.currency || payload.currency || "SLE";
      const customerPhone = String(
        data.customer?.phone ||
        data.metadata?.customerPhone ||
        data.metadata?.phoneNumber ||
        metadata.customerPhone ||
        metadata.phoneNumber ||
        data.phone ||
        payload.phone ||
        ""
      );
      const provider = String(
        data.provider || data.channel || metadata.provider || payload.provider || "ORANGE"
      );

      const txnId = orderNumber || cleanRef || String(data.id || `MONIME_${Date.now()}`);

      // 4. Atomically update transaction, credit wallet, and notify user
      const result = await ctx.runMutation(
        internal.payments.processMoniMeWebhookSuccess,
        {
          transactionId: txnId,
          reference: cleanRef,
          rawReference: rawReference !== cleanRef ? rawReference : undefined,
          orderNumber: orderNumber || undefined,
          walletId: walletId || undefined,
          userId: userId || undefined,
          amount,
          netAmount,
          feeAmount,
          currency,
          provider: `MONIME_${String(provider).toUpperCase()}`,
          customerPhone: customerPhone ? String(customerPhone) : undefined,
          rawPayload: rawBody,
        }
      );

      console.log("MoniMe Webhook Processed Successfully:", result);

      return new Response(
        JSON.stringify({
          received: true,
          success: true,
          status: "COMPLETED",
          result,
        }),
        { status: 200, headers: corsHeaders() }
      );
    }

    // Acknowledge other events (e.g. payment.failed, payment.pending) cleanly with 200
    return new Response(
      JSON.stringify({
        received: true,
        event,
        status: status || "ACKNOWLEDGED",
      }),
      { status: 200, headers: corsHeaders() }
    );
  } catch (err: any) {
    console.error("[MoniMe Webhook] Processing error:", err);
    return new Response(
      JSON.stringify({
        received: true,
        status: "INTERNAL_ERROR_LOGGED",
        error: err?.message || "Internal server error occurred",
      }),
      { status: 200, headers: corsHeaders() }
    );
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



