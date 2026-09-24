// convex/lib/paymentErrors.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Payment Gateway Telemetry, Carrier Error Mapping & Normalization
// Handles carrier-specific failure codes (insufficient funds, invalid subscriber,
// pin timeout), phone sanitization for Sierra Leone telecom networks, and logging.
// ═══════════════════════════════════════════════════════════════════════

export type CarrierErrorCode =
  | "INSUFFICIENT_FUNDS"
  | "INVALID_NUMBER"
  | "PIN_TIMEOUT"
  | "PAYMENT_FAILED"
  | "GATEWAY_ERROR";

export interface ParsedCarrierResponse {
  success: boolean;
  code: CarrierErrorCode | "PAYMENT_INITIATED";
  message: string;
  statusCode: number;
  rawError?: any;
}

/**
 * Normalizes Sierra Leone phone numbers before dispatching to payment gateways.
 * 
 * Rules:
 * - Strips all non-digit characters (+, spaces, dashes, parentheses).
 * - Converts local format with leading 0 (e.g., 076XXXXXX or 078XXXXXX) -> 23276XXXXXX.
 * - Converts 8-digit local format without 0 (e.g., 76XXXXXX) -> 23276XXXXXX.
 * - Fixes accidental double prefix with leading 0 (e.g., 232076XXXXXX) -> 23276XXXXXX.
 * - Leaves standard international format (23276XXXXXX) intact.
 */
export function sanitizeSierraLeonePhone(raw?: string): string {
  if (!raw) return "";
  let digits = raw.replace(/\D/g, "");
  if (!digits) return "";

  // 1. Fix 2320XXXXXXXX (12 digits with accidental local 0 after 232)
  if (digits.startsWith("2320") && digits.length === 12) {
    digits = "232" + digits.substring(4);
  }

  // 2. Standard 11-digit format starting with 232 (e.g., 23276108761)
  if (digits.startsWith("232") && digits.length === 11) {
    return digits;
  }

  // 3. Local 9-digit format with leading 0 (e.g., 076108761) -> 23276108761
  if (digits.startsWith("0") && digits.length === 9) {
    return "232" + digits.substring(1);
  }

  // 4. Local 8-digit format without leading 0 (e.g., 76108761) -> 23276108761
  if (digits.length === 8) {
    return "232" + digits;
  }

  // 5. Fallback if already starts with 232
  if (digits.startsWith("232")) {
    return digits;
  }

  return digits;
}

export type SierraLeoneCarrier = "orange" | "africell" | "qmoney" | "unknown";

/**
 * Automatically detects the Sierra Leone Mobile Money carrier from phone prefix.
 *
 * Rules:
 * - Orange Money: prefixes 71, 72, 73, 74, 75, 76, 78, 79
 * - Africell Afrimoney: prefixes 70, 77, 80, 88, 90, 99, 30, 33
 * - QCell QMoney: prefixes 31, 32, 34
 */
export function detectSierraLeoneCarrier(raw?: string): SierraLeoneCarrier {
  const sanitized = sanitizeSierraLeonePhone(raw);
  if (!sanitized) return "unknown";

  // When sanitized, standard Sierra Leone phone is 232 + 8 digits = 11 digits
  let prefix = "";
  if (sanitized.startsWith("232") && sanitized.length >= 5) {
    prefix = sanitized.substring(3, 5);
  } else if (sanitized.length >= 2) {
    prefix = sanitized.substring(0, 2);
  }

  // Orange Money
  if (["71", "72", "73", "74", "75", "76", "78", "79"].includes(prefix)) {
    return "orange";
  }

  // Africell Afrimoney
  if (["70", "77", "80", "88", "90", "99", "30", "33"].includes(prefix)) {
    return "africell";
  }

  // QCell QMoney
  if (["31", "32", "34"].includes(prefix)) {
    return "qmoney";
  }

  return "unknown";
}

/**
 * Parses raw HTTP status code and response payload from payment gateways
 * (Moneroo, Flutterwave, Paystack, Carrier direct) into structured error codes.
 */
export function parseCarrierResponse(
  statusCode: number,
  responseData: any
): ParsedCarrierResponse {
  // If HTTP status is success (200-299)
  if (statusCode >= 200 && statusCode < 300) {
    const isExplicitError =
      responseData?.status === "error" ||
      responseData?.status === false ||
      responseData?.success === false;

    if (!isExplicitError) {
      return {
        success: true,
        code: "PAYMENT_INITIATED",
        message: "Push prompt sent. Please approve on your phone.",
        statusCode,
      };
    }
  }

  // Serialize entire response to inspect text
  const rawString = (
    typeof responseData === "string"
      ? responseData
      : JSON.stringify(responseData || {})
  ).toUpperCase();

  const errCode = (
    responseData?.code ||
    responseData?.error_code ||
    responseData?.error ||
    ""
  ).toString().toUpperCase();

  const message = (
    responseData?.message ||
    responseData?.error ||
    responseData?.description ||
    ""
  ).toString();

  // ── 1. Insufficient Funds ──────────────────────────────────────────
  if (
    statusCode === 402 ||
    errCode === "INSUFFICIENT_FUNDS" ||
    rawString.includes("INSUFFICIENT_FUNDS") ||
    rawString.includes("INSUFFICIENT_BALANCE") ||
    rawString.includes("LOW_BALANCE") ||
    rawString.includes("NOT_ENOUGH_MONEY") ||
    rawString.includes("NOT_ENOUGH_FUNDS") ||
    rawString.includes("BALANCE_INSUFFICIENT") ||
    rawString.includes("INSUFFICIENT BALANCE")
  ) {
    return {
      success: false,
      code: "INSUFFICIENT_FUNDS",
      message: "Insufficient mobile money balance. Please top up your SIM and try again.",
      statusCode: 400,
      rawError: responseData,
    };
  }

  // ── 2. Invalid Subscriber / Phone Format ───────────────────────────
  if (
    statusCode === 404 ||
    errCode === "SUBSCRIBER_NOT_FOUND" ||
    errCode === "INVALID_PHONE" ||
    errCode === "INVALID_NUMBER" ||
    rawString.includes("SUBSCRIBER_NOT_FOUND") ||
    rawString.includes("SUBSCRIBER NOT FOUND") ||
    rawString.includes("INVALID_PHONE") ||
    rawString.includes("INVALID_NUMBER") ||
    rawString.includes("INVALID MSISDN") ||
    rawString.includes("INVALID_MSISDN") ||
    rawString.includes("NOT_REGISTERED") ||
    rawString.includes("NOT REGISTERED") ||
    rawString.includes("UNREGISTERED") ||
    rawString.includes("SUBSCRIBER_BARRED") ||
    rawString.includes("USER_NOT_FOUND")
  ) {
    return {
      success: false,
      code: "INVALID_NUMBER",
      message: "Invalid or unregistered mobile money phone number.",
      statusCode: 400,
      rawError: responseData,
    };
  }

  // ── 3. Authorization Timeout / User Cancelled ─────────────────────
  if (
    statusCode === 408 ||
    errCode === "PIN_TIMEOUT" ||
    rawString.includes("PIN_TIMEOUT") ||
    rawString.includes("TIMEOUT") ||
    rawString.includes("TIMED_OUT") ||
    rawString.includes("EXPIRED") ||
    rawString.includes("USER_CANCELLED") ||
    rawString.includes("CANCELLED_BY_USER") ||
    rawString.includes("TRANSACTION TIMEOUT")
  ) {
    return {
      success: false,
      code: "PIN_TIMEOUT",
      message: "Authorization prompt expired or was cancelled by user.",
      statusCode: 400,
      rawError: responseData,
    };
  }

  // ── 4. Fallback Payment Failure ───────────────────────────────────
  const userFriendlyMessage =
    message.trim().length > 0 && message.length < 160
      ? message
      : "Payment processing failed. Please verify your details and try again.";

  return {
    success: false,
    code: statusCode >= 500 ? "GATEWAY_ERROR" : "PAYMENT_FAILED",
    message: userFriendlyMessage,
    statusCode: statusCode >= 500 ? 502 : 400,
    rawError: responseData,
  };
}

/**
 * Standardized telemetry logger for payment gateway responses.
 */
export function logGatewayError(
  statusCode: number,
  responseData: any,
  sentPayload: any
): void {
  console.error("Payment Gateway Error:", {
    statusCode,
    responseData,
    sentPayload: {
      ...sentPayload,
      // Redact sensitive authorization if any
      secret_key: sentPayload?.secret_key ? "REDACTED" : undefined,
    },
  });
}
