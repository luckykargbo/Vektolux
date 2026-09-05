// convex/lib/validation.ts
// ═══════════════════════════════════════════════════════════════════════
// Shared input validation helpers for Convex functions.
// ═══════════════════════════════════════════════════════════════════════

/**
 * Validate that a string is non-empty after trimming.
 */
export function requireNonEmpty(value: string, fieldName: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error(`${fieldName} must not be empty`);
  }
  return trimmed;
}

/**
 * Validate that a number is positive (> 0).
 */
export function requirePositive(value: number, fieldName: string): void {
  if (typeof value !== "number" || isNaN(value) || value <= 0) {
    throw new Error(`${fieldName} must be a positive number, got: ${value}`);
  }
}

/**
 * Validate that a number is non-negative (>= 0).
 */
export function requireNonNegative(value: number, fieldName: string): void {
  if (typeof value !== "number" || isNaN(value) || value < 0) {
    throw new Error(`${fieldName} must be non-negative, got: ${value}`);
  }
}

/**
 * Validate basis points (0–10000).
 */
export function requireValidBps(value: number, fieldName: string): void {
  if (!Number.isInteger(value) || value < 0 || value > 10000) {
    throw new Error(
      `${fieldName} must be integer 0–10000 (basis points), got: ${value}`
    );
  }
}

/**
 * Compute platform fee and vendor payout from an amount and fee bps.
 */
export function computeCommissionSplit(
  amount: number,
  feeBps: number
): { platformFee: number; vendorPayout: number } {
  const platformFee = Math.round((amount * feeBps) / 10000);
  const vendorPayout = amount - platformFee;
  return { platformFee, vendorPayout };
}

/**
 * Generate a deterministic idempotency key from components.
 */
export function makeIdempotencyKey(...parts: string[]): string {
  return parts.join("::");
}
