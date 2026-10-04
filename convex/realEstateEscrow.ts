// convex/realEstateEscrow.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Multi-Tier Real Estate Escrow & Settlement Engine
// Implements:
// 1. Inspection Pass (Anti-Bypass Tours with 85/15 Agent/Platform Split)
// 2. Short-Stay Bookings (24-Hour Host Payout Rule + Caution Vault)
// 3. Long-Term Leases (10% Agency Commission + Locked Caution Deposit)
// 4. Land & House Purchases (10/40/50 Gated Milestone Escrow)
// Operating Standard: Sierra Leone New Leones (SLE)
//
// MONEY RULES (enforced here, not in the app):
//  • Every amount is computed on the server from the listing. Amounts sent by the app are ignored.
//  • Funds move ONLY through walletCore (atomic, idempotent, double-entry, with transaction rows).
//  • A contract/pass is FUNDED only when money is really held: from the wallet, from a provider
//    payment verified by Monime, or from a bank transfer confirmed by an admin. Otherwise it stays
//    unfunded (CREATED) and nothing can be released.
//  • The owner's contact details and exact address are never returned to the other party; the
//    admin coordinates inquiries and handovers.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { reContractType } from "./schema";
import { detectSierraLeoneCarrier } from "./lib/paymentErrors";
import { requireSelf, requireParticipantOrAdmin, requireAdminSession } from "./lib/auth";
import { activeListingAgent } from "./listingAgents";
import { isListingPublic } from "./lib/publicListing";
import { bumpListingCounter } from "./listingStats";
import { publicLocation } from "./lib/slLocations";
import {
  fundEscrowFromExternalPayment,
  holdFunds,
  releaseHeldFunds,
  refundHeldFunds,
} from "./walletCore";
import { FeeSnapshot, priceOrder } from "./lib/fees";

const round2 = (n: number) => Math.round(n * 100) / 100;
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

const REF_CONTRACT = "re_escrow";
const REF_PASS = "re_inspection_pass";
/** Tour-fee tiers offered by the app (SLE). Anything else is treated as the default tier. */
const TOUR_FEE_TIERS = [50, 100];
const OTP_MAX_ATTEMPTS = 5;

async function resolveCallerUser(ctx: any, explicitUserId?: string, sessionToken?: string): Promise<Id<"users">> {
  // Identity comes ONLY from the validated session (or JWT identity). A client-supplied
  // user id is merely checked for consistency; it is never a source of identity.
  const { userId } = await requireSelf(ctx, sessionToken, explicitUserId);
  return userId;
}

/** Cryptographically random hex string (length = 2 * bytes). */
function randomHex(bytes: number): string {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
}
/** Cryptographically random N-digit numeric code. */
function randomDigits(n: number): string {
  const a = new Uint32Array(n);
  crypto.getRandomValues(a);
  return Array.from(a, (x) => String(x % 10)).join("");
}
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

/** How much of a contract's money is still held in escrow. */
function heldRemaining(c: any): number {
  if (typeof c.escrowHeldRemaining === "number") return c.escrowHeldRemaining;
  // Contracts created before this field existed.
  return Math.max(0, round2(c.grossAmount - (c.releasedBeneficiaryAmount ?? 0) - (c.refundedClientAmount ?? 0)));
}

async function notify(ctx: any, userId: Id<"users">, title: string, body: string) {
  await ctx.db.insert("user_notifications", {
    userId: userId as string,
    targetType: "single_user",
    title,
    body,
    read: false,
    createdAt: Date.now(),
  });
}

async function walletCovers(ctx: any, userId: Id<"users">, amount: number): Promise<boolean> {
  const w = await ctx.db
    .query("walletBalances")
    .withIndex("by_user_currency", (q: any) => q.eq("userId", userId).eq("currency", "SLE"))
    .first();
  return !!w && w.availableBalance >= amount;
}

// ═══════════════════════════════════════════════════════════════════════
// FUNDING HELPERS (shared with payments.ts for Monime / bank confirmation)
// ═══════════════════════════════════════════════════════════════════════

/** Holds the contract's gross amount from the client's AVAILABLE funds. `soft` reports instead of throwing. */
export async function fundReContractFromWallet(
  ctx: { db: any },
  contractId: Id<"re_escrow_contracts">,
  soft = false
): Promise<{ funded: boolean; reason?: string }> {
  const c = await ctx.db.get(contractId);
  if (!c || c.currentState !== "CREATED") return { funded: false, reason: "The contract is not awaiting payment." };
  if (soft && !(await walletCovers(ctx, c.clientId, c.grossAmount))) {
    return { funded: false, reason: "Available balance is lower than the escrow amount." };
  }
  await holdFunds(ctx, {
    userId: c.clientId,
    amount: c.grossAmount,
    referenceType: REF_CONTRACT,
    referenceId: c._id,
    idempotencyKey: `rec:${c._id}:fund`,
    description: `Escrow funded for ${c.contractCode}`,
    counterpartyId: c.beneficiaryId,
  });
  await ctx.db.patch(c._id, { currentState: "FUNDS_LOCKED", escrowHeldRemaining: c.grossAmount, updatedAt: Date.now() });
  await notify(ctx, c.beneficiaryId, "Escrow funded", `Payment for contract ${c.contractCode} is secured in escrow.`);
  return { funded: true };
}

/** A bank transfer confirmed by an admin funds the contract directly (no wallet top-up). */
export async function fundReContractFromExternal(
  ctx: { db: any },
  contractId: Id<"re_escrow_contracts">,
  provider: string,
  providerReference: string
): Promise<{ funded: boolean; reason?: string }> {
  const c = await ctx.db.get(contractId);
  if (!c || c.currentState !== "CREATED") return { funded: false, reason: "The contract is not awaiting payment." };
  await fundEscrowFromExternalPayment(ctx, {
    userId: c.clientId,
    amount: c.grossAmount,
    provider,
    providerReference,
    referenceType: REF_CONTRACT,
    referenceId: c._id,
    counterpartyId: c.beneficiaryId,
  });
  await ctx.db.patch(c._id, {
    currentState: "FUNDS_LOCKED",
    escrowHeldRemaining: c.grossAmount,
    bankClearingStatus: "CLEARED",
    updatedAt: Date.now(),
  });
  await notify(ctx, c.clientId, "Payment confirmed", `Your payment for contract ${c.contractCode} is secured in escrow.`);
  await notify(ctx, c.beneficiaryId, "Escrow funded", `Payment for contract ${c.contractCode} is secured in escrow.`);
  return { funded: true };
}

/** Holds an inspection-pass fee from the client's available funds. */
export async function fundInspectionPassFromWallet(
  ctx: { db: any },
  passId: Id<"re_inspection_passes">,
  soft = false
): Promise<{ funded: boolean; reason?: string }> {
  const p = await ctx.db.get(passId);
  if (!p || p.status !== "CREATED") return { funded: false, reason: "The pass is not awaiting payment." };
  if (soft && !(await walletCovers(ctx, p.clientId, p.tourFee))) {
    return { funded: false, reason: "Available balance is lower than the pass fee." };
  }
  await holdFunds(ctx, {
    userId: p.clientId,
    amount: p.tourFee,
    referenceType: REF_PASS,
    referenceId: p._id,
    idempotencyKey: `rip:${p._id}:fund`,
    description: "Viewing tour pass fee held in escrow",
    counterpartyId: p.agentId,
  });
  await ctx.db.patch(p._id, { status: "FUNDS_LOCKED" });
  return { funded: true };
}

// ═══════════════════════════════════════════════════════════════════════
// 1. INSPECTION PASS (ANTI-BYPASS TOURS)
// ═══════════════════════════════════════════════════════════════════════

export const initiateInspectionPass = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    propertyListingId: v.id("realEstateListings"),
    clientId: v.optional(v.string()),
    preferredAgentId: v.optional(v.string()), // ignored: the tour is run by the owner or the owner's authorised agent
    tourFee: v.optional(v.number()), // one of the offered tiers; anything else = default tier
    scheduledTimestamp: v.number(),
    paymentRail: v.optional(v.string()), // WALLET, or a mobile-money provider (paid through Monime)
    paymentPhone: v.optional(v.string()),
  },
  returns: v.object({
    passId: v.string(),
    qrHash: v.string(),
    otpCode: v.string(),
    tourFee: v.number(),
    agentNetFee: v.number(),
    platformFee: v.number(),
    expiresAt: v.number(),
    status: v.string(),
    assignedAgentName: v.string(),
    maskedNeighborhood: v.string(),
  }),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx, args.clientId, args.sessionToken);
    const property = await ctx.db.get(args.propertyListingId);
    if (!property || !isListingPublic(property)) {
      throw new Error("This property is not available.");
    }
    if (property.ownerId === currentUserId) {
      throw new Error("You cannot book an inspection tour on your own property.");
    }
    const now = Date.now();
    if (!(args.scheduledTimestamp > now - 60 * 60 * 1000) || args.scheduledTimestamp > now + 90 * 24 * 3600 * 1000) {
      throw new Error("Choose a viewing time within the next 90 days.");
    }

    // The fee is one of the server-side tiers; it can never be chosen freely by the client.
    const fee = TOUR_FEE_TIERS.includes(args.tourFee ?? -1) ? (args.tourFee as number) : TOUR_FEE_TIERS[0];
    // Fee & Commission Engine (default: platform keeps 15% of the tour fee, the agent 85%).
    // tourFee (what the client pays and what is held) includes any admin-enabled buyer fee.
    const fees = await priceOrder(ctx, "re_viewing_pass", fee, { hasAgent: false, now });
    const tourFee = fees.buyerTotal;
    const platformFee = fees.platformTotal;
    const agentNetFee = fees.payeeNet;

    // The tour is run by the agent the OWNER authorised for this listing (active, still eligible),
    // otherwise by the owner. A client can no longer route the tour fee to an agent of their choice.
    const link = await activeListingAgent(ctx, "property", property._id as string, now);
    const useAgent = link !== null && link.agentId !== currentUserId;
    const agentId: Id<"users"> = useAgent ? link!.agentId : property.ownerId;
    const agentUser = await ctx.db.get(agentId);

    const rail = args.paymentRail ?? "WALLET";
    const qrHash = `VK-TOUR-${randomHex(12)}`;
    const otpCode = randomDigits(4);
    const otpExpiresAt = args.scheduledTimestamp + 4 * 3600 * 1000;

    const passId = await ctx.db.insert("re_inspection_passes", {
      propertyListingId: property._id,
      clientId: currentUserId,
      agentId,
      tourFee,
      platformFee,
      agentNetFee,
      feeSnapshot: fees,
      agentAuthorizationId: useAgent ? link!.authorizationId : undefined,
      qrHash,
      otpCode,
      otpExpiresAt,
      status: "CREATED", // becomes FUNDS_LOCKED only when the fee is really held
      scheduledAt: args.scheduledTimestamp,
      isAddressUnmasked: false,
      failedAttempts: 0,
      createdAt: now,
    });

    let status = "CREATED";
    if (rail === "WALLET") {
      await fundInspectionPassFromWallet(ctx, passId); // throws INSUFFICIENT_FUNDS -> nothing is created
      status = "FUNDS_LOCKED";
    }
    await bumpListingCounter(ctx, property._id, "viewingRequestCount");

    return {
      passId: passId as string,
      qrHash,
      otpCode,
      tourFee,
      agentNetFee,
      platformFee,
      expiresAt: otpExpiresAt,
      status,
      assignedAgentName: agentUser?.name ?? "Vektolux Verified Field Agent",
      // Privacy: only the broad public location. No contact details, no street address.
      maskedNeighborhood: `${publicLocation(property.city, property.district)} (exact location is shared by Vektolux after payment)`,
    };
  },
});

/** The assigned agent (or an admin) verifies the client's arrival with the pass QR / OTP. */
export const verifyInspectionPass = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    passId: v.id("re_inspection_passes"),
    scannedQrHash: v.optional(v.string()),
    enteredOtp: v.optional(v.string()),
    agentGpsLat: v.optional(v.number()),
    agentGpsLng: v.optional(v.number()),
    // legacy argument names still sent by older app builds
    agentId: v.optional(v.string()),
    otpOrQrHash: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.optional(v.string()),
    agentNetPaid: v.optional(v.number()),
    publicLocation: v.optional(v.string()),
    message: v.string(),
    verifiedAt: v.optional(v.number()),
    errorCode: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const pass = await ctx.db.get(args.passId);
    if (!pass) throw new Error("Inspection pass not found");
    // Only the agent conducting the tour or an admin may verify it.
    await requireParticipantOrAdmin(ctx, args.sessionToken, [pass.agentId]);

    if (pass.status === "FULLY_SETTLED" || pass.status === "MILESTONE_VERIFIED") {
      throw new Error("This inspection pass has already been verified and settled.");
    }
    if (pass.status !== "FUNDS_LOCKED") {
      return { success: false, errorCode: "PASS_NOT_FUNDED", message: "This pass has not been paid yet, so it cannot be verified." };
    }
    if ((pass.failedAttempts ?? 0) >= OTP_MAX_ATTEMPTS) {
      return { success: false, errorCode: "PASS_LOCKED", message: "Too many incorrect codes. Contact Vektolux support to unlock this pass." };
    }
    const now = Date.now();
    if (now > pass.otpExpiresAt + 24 * 3600 * 1000) {
      return { success: false, errorCode: "PASS_EXPIRED", message: "This pass has expired. The client can request a refund." };
    }

    const qr = (args.scannedQrHash ?? args.otpOrQrHash ?? "").trim();
    const otp = (args.enteredOtp ?? args.otpOrQrHash ?? "").trim();
    const matches = (qr.length > 0 && safeEqual(qr, pass.qrHash)) || (otp.length > 0 && safeEqual(otp, pass.otpCode));
    if (!matches) {
      // A failure is RETURNED (not thrown) so the attempt counter is saved.
      const attempts = (pass.failedAttempts ?? 0) + 1;
      await ctx.db.patch(pass._id, { failedAttempts: attempts });
      return {
        success: false,
        errorCode: "INVALID_CODE",
        message: attempts >= OTP_MAX_ATTEMPTS ? "Too many incorrect codes. This pass is now locked." : "Invalid code. Check the QR or the 4-digit OTP.",
      };
    }

    const property = await ctx.db.get(pass.propertyListingId);
    if (!property) throw new Error("Associated property listing not found");

    // Escrow -> agent (85%) + platform (15%) through the wallet core.
    await releaseHeldFunds(ctx, {
      buyerId: pass.clientId,
      recipientId: pass.agentId,
      amount: pass.tourFee,
      platformFee: pass.platformFee,
      referenceType: REF_PASS,
      referenceId: pass._id,
      idempotencyKey: `rip:${pass._id}:settle`,
    });

    await ctx.db.patch(pass._id, {
      status: "FULLY_SETTLED",
      verifiedAt: now,
      agentGpsLat: args.agentGpsLat,
      agentGpsLng: args.agentGpsLng,
    });

    // Privacy: the agent/client never receive the owner's phone, name or exact address from here.
    // Vektolux coordinates the next step with the owner.
    return {
      success: true,
      status: "FULLY_SETTLED",
      agentNetPaid: pass.agentNetFee,
      publicLocation: publicLocation(property.city, property.district),
      message: "Visit verified and your tour fee was credited. Vektolux will coordinate the next steps with the property owner.",
      verifiedAt: now,
    };
  },
});

/** The client (after the pass expired unused) or an admin refunds a funded, unverified pass. */
export const refundInspectionPass = mutation({
  args: { sessionToken: v.optional(v.string()), passId: v.id("re_inspection_passes") },
  handler: async (ctx, args) => {
    const pass = await ctx.db.get(args.passId);
    if (!pass) throw new Error("Inspection pass not found");
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [pass.clientId]);
    if (pass.status !== "FUNDS_LOCKED") throw new Error(`A pass in status ${pass.status} cannot be refunded.`);
    if (!who.isAdmin && Date.now() <= pass.otpExpiresAt + 24 * 3600 * 1000) {
      throw new Error("The pass is still valid. It can be refunded after it expires unused.");
    }
    await refundHeldFunds(ctx, {
      userId: pass.clientId,
      amount: pass.tourFee,
      referenceType: REF_PASS,
      referenceId: pass._id,
      idempotencyKey: `rip:${pass._id}:refund`,
    });
    await ctx.db.patch(pass._id, { status: "REFUNDED" });
    return { success: true, status: "REFUNDED", refunded: pass.tourFee };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. MASTER REAL ESTATE ESCROW: STAYS, LEASES & LAND PURCHASES
// ═══════════════════════════════════════════════════════════════════════

export const initiateRealEstateEscrow = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    contractType: reContractType,
    propertyListingId: v.id("realEstateListings"),
    clientId: v.optional(v.string()),
    nightsCount: v.optional(v.number()),
    leaseDurationMonths: v.optional(v.number()),
    paymentRail: v.optional(v.string()), // MOBILE_MONEY, BANK_TRANSFER, WALLET
    paymentPhone: v.optional(v.string()),
    bankEscrowReference: v.optional(v.string()),
    // Accepted for older app builds but IGNORED: the server prices the contract.
    baseAmount: v.optional(v.number()),
    cautionDepositAmount: v.optional(v.number()),
  },
  returns: v.object({
    contractId: v.string(),
    contractCode: v.string(),
    contractType: v.string(),
    grossEscrowAmount: v.number(),
    cautionDeposit: v.number(),
    platformFee: v.number(),
    agentCommission: v.number(),
    netBeneficiaryExpected: v.number(),
    buyerFee: v.optional(v.number()),
    status: v.string(),
    bankEscrowReference: v.optional(v.string()),
    paymentRail: v.optional(v.string()),
    detectedCarrier: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx, args.clientId, args.sessionToken);
    const property = await ctx.db.get(args.propertyListingId);
    if (!property || !isListingPublic(property)) {
      throw new Error("This property is not available.");
    }
    if (property.ownerId === currentUserId) {
      throw new Error("You cannot create an escrow contract for your own property.");
    }

    const now = Date.now();
    const contractCode = `VK-RE-${now.toString().slice(-6)}-${Math.floor(1000 + Math.random() * 9000)}`;
    const price = property.price;
    if (!(price > 0) || !Number.isFinite(price)) throw new Error("This listing has no valid price.");

    let baseAmount = 0;
    let cautionDeposit = 0;
    let platformFee = 0;
    let agentCommission = 0;
    let netBeneficiary = 0;
    let grossEscrow = 0;
    let leaseMonths: number | undefined;
    let fees: FeeSnapshot;
    let agentLink: Awaited<ReturnType<typeof activeListingAgent>> = null;
    // Fees from the Fee & Commission Engine (defaults = 10% stay, 10% lease commission with a 15%
    // platform share, 5% purchase, as before). platformFee = everything the platform keeps.

    if (args.contractType === "SHORT_STAY_BOOKING") {
      if (property.category !== "hourly_guesthouse") throw new Error("This property is not available for short stays.");
      const nights = Math.floor(args.nightsCount ?? 1);
      if (!(nights >= 1 && nights <= 90)) throw new Error("A stay must be between 1 and 90 nights.");
      baseAmount = round2(price * nights);
      cautionDeposit = round2(clamp(baseAmount * 0.25, 300, 5000));
      fees = await priceOrder(ctx, "re_short_stay", baseAmount, { hasAgent: false, now });
      platformFee = fees.platformTotal;
      netBeneficiary = fees.payeeNet;
      grossEscrow = round2(fees.buyerTotal + cautionDeposit);
    } else if (args.contractType === "LONG_TERM_LEASE") {
      if (property.category !== "long_term_rent") throw new Error("This property is not available for long-term lease.");
      leaseMonths = Math.floor(args.leaseDurationMonths ?? 12);
      if (!(leaseMonths >= 1 && leaseMonths <= 60)) throw new Error("A lease must be between 1 and 60 months.");
      baseAmount = round2((price / 12) * leaseMonths); // listing price is the annual rent
      cautionDeposit = round2(clamp(price / 12, 500, 50000));
      // An agent commission is charged ONLY when the owner has a valid, active authorised agent for
      // this listing (and the fee rule has a commission). No authorised agent → no commission.
      const link = await activeListingAgent(ctx, "property", property._id as string, now);
      agentLink = link && link.agentId !== currentUserId ? link : null;
      fees = await priceOrder(ctx, "re_lease", baseAmount, { hasAgent: agentLink !== null, now });
      platformFee = fees.platformTotal;
      agentCommission = fees.agentCommissionNet;
      netBeneficiary = fees.payeeNet;
      grossEscrow = round2(fees.buyerTotal + cautionDeposit);
    } else {
      if (property.category !== "sale") throw new Error("This property is not for sale.");
      baseAmount = round2(price);
      fees = await priceOrder(ctx, "re_land_purchase", baseAmount, { hasAgent: false, now });
      platformFee = fees.platformTotal;
      netBeneficiary = fees.payeeNet;
      grossEscrow = fees.buyerTotal;
    }

    const resolvedRail = args.paymentRail ?? "MOBILE_MONEY";
    let detectedCarrier: string | undefined;
    if (args.paymentPhone) {
      const carrier = detectSierraLeoneCarrier(args.paymentPhone);
      if (carrier !== "unknown") detectedCarrier = carrier;
    }

    let bankEscrowReference = args.bankEscrowReference;
    let bankClearingStatus: "PENDING_TRANSFER" | "CLEARED" | undefined;
    if (resolvedRail === "BANK_TRANSFER") {
      if (!bankEscrowReference) bankEscrowReference = `VKTLX-DEAL-${Math.floor(1000 + Math.random() * 9000)}`;
      bankClearingStatus = "PENDING_TRANSFER";
    }

    const contractId = await ctx.db.insert("re_escrow_contracts", {
      contractCode,
      contractType: args.contractType,
      propertyListingId: property._id,
      clientId: currentUserId,
      beneficiaryId: property.ownerId,
      agentId: agentLink ? agentLink.agentId : property.ownerId,
      agentAuthorizationId: agentLink ? agentLink.authorizationId : undefined,
      grossAmount: grossEscrow,
      cautionDepositAmount: cautionDeposit,
      platformFeeAmount: platformFee,
      agentCommissionAmount: agentCommission,
      netBeneficiaryExpected: netBeneficiary,
      releasedBeneficiaryAmount: 0,
      refundedClientAmount: 0,
      paymentRail: resolvedRail,
      bankEscrowReference,
      bankClearingStatus,
      detectedCarrier,
      currentState: "CREATED", // FUNDS_LOCKED only once money is really held
      leaseDurationMonths: leaseMonths,
      feeSnapshot: fees,
      createdAt: now,
      updatedAt: now,
    });

    if (cautionDeposit > 0) {
      await ctx.db.insert("re_caution_deposits", {
        contractId,
        originalDepositAmount: cautionDeposit,
        heldAmount: cautionDeposit,
        deductionClaimAmount: 0,
        refundedAmount: 0,
        status: "LOCKED",
        inventoryChecklistSigned: false,
        createdAt: now,
      });
    }

    if (args.contractType === "LAND_PURCHASE_MILESTONE") {
      const m1Amount = round2(grossEscrow * 0.10);
      const m2Amount = round2(grossEscrow * 0.40);
      const m3Amount = round2(grossEscrow - m1Amount - m2Amount);
      const defs = [
        { i: 1, t: "Title Search & Root Confirmation (10%)", p: 10, a: m1Amount, r: "Certified OARG (Roxy Building) Search Report confirming clean title" },
        { i: 2, t: "Cadastral Survey Plan & Deed Verification (40%)", p: 40, a: m2Amount, r: "Licensed Surveyor beacon sign-off + MLHCP Cadastral confirmation" },
        { i: 3, t: "Final Conveyance Signing & OARG Registration (50%)", p: 50, a: m3Amount, r: "Signed Deed of Conveyance + OARG Volume & Page registration stamp" },
      ];
      for (const d of defs) {
        await ctx.db.insert("re_escrow_milestones", {
          contractId,
          milestoneIndex: d.i,
          title: d.t,
          targetPercentage: d.p,
          amount: d.a,
          verificationRequirement: d.r,
          proofDocumentUrls: [],
          isVerified: false,
          state: "CREATED",
          createdAt: now,
        });
      }
    }

    let status = "CREATED";
    if (resolvedRail === "WALLET") {
      await fundReContractFromWallet(ctx, contractId); // throws INSUFFICIENT_FUNDS -> nothing is created
      status = "FUNDS_LOCKED";
    }

    return {
      contractId: contractId as string,
      contractCode,
      contractType: args.contractType,
      grossEscrowAmount: grossEscrow,
      cautionDeposit,
      platformFee,
      agentCommission,
      netBeneficiaryExpected: netBeneficiary,
      buyerFee: fees.buyerFee,
      status,
      bankEscrowReference,
      paymentRail: resolvedRail,
      detectedCarrier,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. SHORT-STAY / LEASE 24-HOUR CHECK-IN RULE & CAUTION REFUNDS
// ═══════════════════════════════════════════════════════════════════════

export const checkInShortStay = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    contractId: v.id("re_escrow_contracts"),
    doorQrCode: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    checkInTimestamp: v.number(),
    autoReleaseTimestamp24h: v.number(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Escrow contract not found");
    // The guest/tenant confirms arrival; starting the payout clock is not a host/third-party action.
    await requireParticipantOrAdmin(ctx, args.sessionToken, [contract.clientId]);

    if (contract.contractType !== "SHORT_STAY_BOOKING" && contract.contractType !== "LONG_TERM_LEASE") {
      throw new Error("The 24-hour check-in rule applies to short stays and leases only.");
    }
    if (contract.currentState !== "FUNDS_LOCKED") {
      throw new Error(`Check-in requires a funded contract (current state: ${contract.currentState}).`);
    }

    const now = Date.now();
    const autoReleaseTime = now + 24 * 3600 * 1000;
    await ctx.db.patch(contract._id, {
      currentState: "CHECKED_IN",
      stayCheckInTimestamp: now,
      stay24hAutoReleaseTimestamp: autoReleaseTime,
      updatedAt: now,
    });

    return {
      success: true,
      status: "CHECKED_IN",
      checkInTimestamp: now,
      autoReleaseTimestamp24h: autoReleaseTime,
      message: "Checked in! The payout will be released to the owner in 24 hours if no defect dispute is raised.",
    };
  },
});

/** Pays the host/landlord (and agent commission / platform fee) from escrow. Shared by the 24h rule and admin resolution. */
async function payoutContract(ctx: any, contract: any, key: string) {
  const base = contract.netBeneficiaryExpected + (contract.contractType === "SHORT_STAY_BOOKING" ? contract.platformFeeAmount : 0);
  if (contract.contractType === "LONG_TERM_LEASE") {
    // Landlord receives the rent net of any owner fee; the platform keeps owner/buyer fees; the
    // commission is split between the agent and the platform — all per the order's fee snapshot.
    const snap = contract.feeSnapshot;
    const ownerAndBuyerFees = snap ? round2(snap.ownerFee + snap.buyerFee) : 0;
    const commissionShare = snap ? snap.platformAgentShare : contract.platformFeeAmount;
    const agentGross = snap ? snap.agentCommissionGross : round2(contract.agentCommissionAmount + contract.platformFeeAmount);
    const rentAmount = round2(contract.netBeneficiaryExpected + ownerAndBuyerFees);
    await releaseHeldFunds(ctx, {
      buyerId: contract.clientId,
      recipientId: contract.beneficiaryId,
      amount: rentAmount,
      platformFee: ownerAndBuyerFees,
      referenceType: REF_CONTRACT,
      referenceId: contract._id,
      idempotencyKey: `rec:${contract._id}:${key}:rent`,
    });
    if (agentGross > 0) {
      await releaseHeldFunds(ctx, {
        buyerId: contract.clientId,
        recipientId: contract.agentId,
        amount: agentGross,
        platformFee: commissionShare,
        referenceType: REF_CONTRACT,
        referenceId: contract._id,
        idempotencyKey: `rec:${contract._id}:${key}:commission`,
      });
    }
    return round2(rentAmount + agentGross);
  }
  // short stay: the stay cost (net to host + platform fee)
  await releaseHeldFunds(ctx, {
    buyerId: contract.clientId,
    recipientId: contract.beneficiaryId,
    amount: round2(base),
    platformFee: contract.platformFeeAmount,
    referenceType: REF_CONTRACT,
    referenceId: contract._id,
    idempotencyKey: `rec:${contract._id}:${key}:stay`,
  });
  return round2(base);
}

export const releaseShortStayPayout24h = mutation({
  args: {
    contractId: v.id("re_escrow_contracts"),
    adminForceOverride: v.optional(v.boolean()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    amountReleasedToHost: v.number(),
    platformFeeRealized: v.number(),
  }),
  handler: async (ctx, args) => {
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Contract not found");
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [contract.clientId, contract.beneficiaryId]);

    if (contract.currentState !== "CHECKED_IN") {
      throw new Error(`Contract must be in CHECKED_IN state. Current: ${contract.currentState}`);
    }
    const now = Date.now();
    if (args.adminForceOverride) {
      if (!who.isAdmin) throw new Error("Unauthorized: Only administrators can force early escrow release.");
    } else if (contract.stay24hAutoReleaseTimestamp && now < contract.stay24hAutoReleaseTimestamp) {
      const remainingMinutes = Math.ceil((contract.stay24hAutoReleaseTimestamp - now) / 60000);
      throw new Error(`24-hour holding period still active. ${remainingMinutes} minutes remaining before auto-disbursal.`);
    }

    const openDisputes = await ctx.db
      .query("re_escrow_disputes")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .collect();
    if (openDisputes.some((d: any) => d.status === "OPENED" || d.status === "EVIDENCE_SUBMITTED")) {
      throw new Error("Payout cannot be released while an active dispute is in arbitration.");
    }

    const released = await payoutContract(ctx, contract, "payout");
    const newState = contract.cautionDepositAmount > 0 ? "MILESTONE_VERIFIED" : "FULLY_SETTLED";
    await ctx.db.patch(contract._id, {
      currentState: newState,
      releasedBeneficiaryAmount: contract.netBeneficiaryExpected,
      escrowHeldRemaining: round2(heldRemaining(contract) - released),
      updatedAt: now,
    });

    return {
      success: true,
      status: newState,
      amountReleasedToHost: contract.netBeneficiaryExpected,
      platformFeeRealized: contract.platformFeeAmount,
    };
  },
});

export const refundCautionDeposit = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    contractId: v.id("re_escrow_contracts"),
    inspectionPassedClean: v.boolean(),
    damageDeductionAmount: v.optional(v.number()),
    notes: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    refundedToClient: v.number(),
    deductedToHost: v.number(),
    status: v.string(),
  }),
  handler: async (ctx, args) => {
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Contract not found");
    // The host/beneficiary or an admin settles the caution deposit. The HOST cannot pay themselves
    // out of the client's deposit: a damage claim (> 0) is recorded and the deposit stays held
    // (IN_DISPUTE) until an administrator settles it with the awarded amount. Clean = refund now.
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [contract.beneficiaryId]);
    if (args.damageDeductionAmount !== undefined && !(Number.isFinite(args.damageDeductionAmount) && args.damageDeductionAmount >= 0)) {
      throw new Error("Invalid damage deduction amount.");
    }
    if (contract.currentState === "CREATED" || contract.currentState === "UNDER_ARBITRATION" || contract.currentState === "FULLY_SETTLED" || contract.currentState === "REFUNDED") {
      throw new Error(`The caution deposit cannot be settled while the contract is ${contract.currentState}.`);
    }

    const caution = await ctx.db
      .query("re_caution_deposits")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .first();
    if (!caution) throw new Error("No caution deposit record found for this contract");
    const claimPending = caution.status === "IN_DISPUTE";
    if (caution.status !== "LOCKED" && !(claimPending && who.isAdmin)) {
      throw new Error(claimPending ? "A damage claim on this deposit is awaiting an administrator's decision." : "Caution deposit has already been settled");
    }

    const now = Date.now();
    const claimed = !args.inspectionPassedClean && (args.damageDeductionAmount ?? 0) > 0;
    if (claimed && !who.isAdmin) {
      const claimAmount = round2(Math.min(args.damageDeductionAmount!, caution.heldAmount));
      await ctx.db.patch(caution._id, {
        status: "IN_DISPUTE",
        deductionClaimAmount: claimAmount,
        checkoutNotes: args.notes,
      });
      await notify(ctx, contract.clientId, "Damage claim on your deposit", `The host claimed ${claimAmount} from the caution deposit on ${contract.contractCode}. Your deposit stays held until Vektolux decides.`);
      return { success: true, refundedToClient: 0, deductedToHost: 0, status: "CAUTION_CLAIM_PENDING" };
    }
    let refundedAmount = caution.heldAmount;
    let deductionAmount = 0;
    if (!args.inspectionPassedClean && args.damageDeductionAmount && args.damageDeductionAmount > 0) {
      deductionAmount = round2(Math.min(args.damageDeductionAmount, caution.heldAmount));
      refundedAmount = round2(caution.heldAmount - deductionAmount);
    }

    if (deductionAmount > 0) {
      await releaseHeldFunds(ctx, {
        buyerId: contract.clientId,
        recipientId: contract.beneficiaryId,
        amount: deductionAmount,
        platformFee: 0,
        referenceType: REF_CONTRACT,
        referenceId: contract._id,
        idempotencyKey: `rec:${contract._id}:caution-claim`,
      });
    }
    if (refundedAmount > 0) {
      await refundHeldFunds(ctx, {
        userId: contract.clientId,
        amount: refundedAmount,
        referenceType: REF_CONTRACT,
        referenceId: contract._id,
        idempotencyKey: `rec:${contract._id}:caution-refund`,
      });
    }

    await ctx.db.patch(caution._id, {
      status: deductionAmount > 0 ? "DEDUCTED_PARTIAL" : "REFUNDED_CLEAN",
      refundedAmount,
      deductionClaimAmount: deductionAmount,
      inventoryChecklistSigned: true,
      checkoutNotes: args.notes,
      settledAt: now,
    });

    // The contract is fully settled only when the rent/payout has ALSO been released.
    const rentReleased = (contract.releasedBeneficiaryAmount ?? 0) > 0;
    const newState = rentReleased ? "FULLY_SETTLED" : contract.currentState;
    await ctx.db.patch(contract._id, {
      currentState: newState,
      refundedClientAmount: round2((contract.refundedClientAmount ?? 0) + refundedAmount),
      escrowHeldRemaining: round2(heldRemaining(contract) - caution.heldAmount),
      updatedAt: now,
    });

    return { success: true, refundedToClient: refundedAmount, deductedToHost: deductionAmount, status: newState };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. LAND & HOUSE PURCHASE MILESTONES (10 / 40 / 50 GATED RELEASE)
// ═══════════════════════════════════════════════════════════════════════

export const verifyAndReleaseLandMilestone = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    contractId: v.id("re_escrow_contracts"),
    milestoneIndex: v.number(), // 1, 2, or 3
    proofDocumentUrls: v.array(v.string()),
    legalNotes: v.optional(v.string()),
    verifiedByAdminId: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    milestoneIndex: v.number(),
    amountReleased: v.number(),
    contractState: v.string(),
    remainingInEscrow: v.number(),
  }),
  handler: async (ctx, args) => {
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Contract not found");
    // Legal milestone verification is an admin-only action.
    await requireAdminSession(ctx, args.sessionToken);

    if (contract.contractType !== "LAND_PURCHASE_MILESTONE") {
      throw new Error("Milestone releases only apply to Land & House Purchases");
    }
    if (contract.currentState !== "FUNDS_LOCKED" && contract.currentState !== "MILESTONE_VERIFIED") {
      throw new Error(`Milestones can be released only for a funded contract (current state: ${contract.currentState}).`);
    }

    const milestones = await ctx.db
      .query("re_escrow_milestones")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .collect();
    milestones.sort((a: any, b: any) => a.milestoneIndex - b.milestoneIndex);
    const milestone = milestones.find((m: any) => m.milestoneIndex === args.milestoneIndex);
    if (!milestone) throw new Error(`Milestone ${args.milestoneIndex} not found`);
    if (milestone.state === "FULLY_SETTLED") throw new Error(`Milestone ${args.milestoneIndex} has already been released`);
    if (args.milestoneIndex > 1) {
      const prev = milestones.find((m: any) => m.milestoneIndex === args.milestoneIndex - 1);
      if (!prev || prev.state !== "FULLY_SETTLED") {
        throw new Error(`Cannot release Milestone ${args.milestoneIndex} before Milestone ${args.milestoneIndex - 1} is verified and settled`);
      }
    }

    // The 5% platform fee is collected pro-rata across the milestones (the last takes the remainder).
    const feeOf = (m: any) => round2((contract.platformFeeAmount * m.amount) / contract.grossAmount);
    const isLast = milestones.every((m: any) => m.milestoneIndex === milestone.milestoneIndex || m.state === "FULLY_SETTLED");
    const feeSoFar = milestones
      .filter((m: any) => m.state === "FULLY_SETTLED")
      .reduce((sum: number, m: any) => sum + feeOf(m), 0);
    const fee = isLast ? round2(contract.platformFeeAmount - feeSoFar) : feeOf(milestone);

    const now = Date.now();
    await releaseHeldFunds(ctx, {
      buyerId: contract.clientId,
      recipientId: contract.beneficiaryId,
      amount: milestone.amount,
      platformFee: Math.min(Math.max(fee, 0), milestone.amount),
      referenceType: REF_CONTRACT,
      referenceId: contract._id,
      idempotencyKey: `rec:${contract._id}:milestone:${milestone.milestoneIndex}`,
    });

    await ctx.db.patch(milestone._id, {
      state: "FULLY_SETTLED",
      isVerified: true,
      proofDocumentUrls: args.proofDocumentUrls.slice(0, 20),
      releasedAt: now,
    });

    const newReleased = round2((contract.releasedBeneficiaryAmount ?? 0) + (milestone.amount - Math.max(fee, 0)));
    const remaining = round2(heldRemaining(contract) - milestone.amount);
    const contractNewState = isLast ? "FULLY_SETTLED" : "MILESTONE_VERIFIED";
    await ctx.db.patch(contract._id, {
      releasedBeneficiaryAmount: newReleased,
      escrowHeldRemaining: remaining,
      currentState: contractNewState,
      updatedAt: now,
    });

    return {
      success: true,
      milestoneIndex: args.milestoneIndex,
      amountReleased: milestone.amount,
      contractState: contractNewState,
      remainingInEscrow: Math.max(0, remaining),
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. DISPUTES & ARBITRATION
// ═══════════════════════════════════════════════════════════════════════

export const raiseRealEstateDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    contractId: v.id("re_escrow_contracts"),
    claimantUserId: v.optional(v.string()),
    claimantRole: v.string(), // CLIENT, HOST, LANDLORD, AGENT
    reason: v.string(),
    claimedRepairCost: v.number(),
    evidenceMediaUrls: v.array(v.string()),
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const callerId = await resolveCallerUser(ctx, args.claimantUserId, args.sessionToken);
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Contract not found");
    // Only a party to the contract may freeze it.
    if (![contract.clientId, contract.beneficiaryId, contract.agentId].some((id) => String(id) === String(callerId))) {
      throw new Error("Unauthorized: You are not a party to this contract.");
    }
    if (!["FUNDS_LOCKED", "CHECKED_IN", "MILESTONE_VERIFIED"].includes(contract.currentState)) {
      throw new Error(`A dispute cannot be opened for a contract in state ${contract.currentState}.`);
    }
    if (!(Number.isFinite(args.claimedRepairCost) && args.claimedRepairCost >= 0)) throw new Error("Invalid claimed amount.");

    const now = Date.now();
    const disputeId = await ctx.db.insert("re_escrow_disputes", {
      contractId: contract._id,
      openedByUserId: callerId,
      claimantRole: args.claimantRole.slice(0, 40),
      reason: args.reason.slice(0, 2000),
      claimedRepairCost: args.claimedRepairCost,
      evidenceMediaUrls: args.evidenceMediaUrls.slice(0, 20),
      status: "OPENED",
      openedAt: now,
    });
    await ctx.db.patch(contract._id, { currentState: "UNDER_ARBITRATION", updatedAt: now });
    return disputeId as string;
  },
});

/** Admin ruling on a disputed contract: refund the client, or release the payout (caution is refunded). Audited via the dispute record. */
export const adminResolveRealEstateDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    contractId: v.id("re_escrow_contracts"),
    resolution: v.union(v.literal("refund_client"), v.literal("release_beneficiary")),
    notes: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    if (args.notes.trim().length < 5) throw new Error("Resolution notes are required.");
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Contract not found");
    if (contract.currentState !== "UNDER_ARBITRATION") throw new Error("Only a contract under arbitration can be resolved here.");
    if (args.resolution === "release_beneficiary" && contract.contractType === "LAND_PURCHASE_MILESTONE") {
      throw new Error("Land purchases are released milestone by milestone. Use refund_client or the milestone verification.");
    }

    const held = heldRemaining(contract);
    if (!(held > 0)) throw new Error("Nothing is held for this contract.");
    const caution = await ctx.db
      .query("re_caution_deposits")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .first();
    const cautionHeld = caution && caution.status === "LOCKED" ? caution.heldAmount : 0;
    const now = Date.now();
    let paidOut = 0;

    if (args.resolution === "release_beneficiary") {
      if ((contract.releasedBeneficiaryAmount ?? 0) === 0) paidOut = await payoutContract(ctx, contract, "dispute");
    }
    const refundable = round2(held - paidOut);
    if (refundable > 0) {
      await refundHeldFunds(ctx, {
        userId: contract.clientId,
        amount: refundable,
        referenceType: REF_CONTRACT,
        referenceId: contract._id,
        idempotencyKey: `rec:${contract._id}:dispute-refund`,
      });
    }
    if (caution && cautionHeld > 0) {
      await ctx.db.patch(caution._id, { status: "REFUNDED_CLEAN", refundedAmount: cautionHeld, settledAt: now });
    }

    const newState = args.resolution === "refund_client" ? "REFUNDED" : "FULLY_SETTLED";
    await ctx.db.patch(contract._id, {
      currentState: newState,
      escrowHeldRemaining: 0,
      refundedClientAmount: round2((contract.refundedClientAmount ?? 0) + refundable),
      releasedBeneficiaryAmount:
        args.resolution === "release_beneficiary" && paidOut > 0 ? contract.netBeneficiaryExpected : contract.releasedBeneficiaryAmount,
      updatedAt: now,
    });
    const disputes = await ctx.db
      .query("re_escrow_disputes")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .collect();
    for (const d of disputes) {
      if (d.status === "OPENED" || d.status === "EVIDENCE_SUBMITTED" || d.status === "IN_CONCILIATION") {
        await ctx.db.patch(d._id, {
          status: "ADJUDICATED_ADMIN",
          adjudicatedByAdminId: adminId,
          adjudicationNotes: args.notes.trim().slice(0, 1000),
          resolvedAt: now,
        });
      }
    }
    for (const uid of [contract.clientId, contract.beneficiaryId]) {
      await notify(ctx, uid, "Dispute resolved", `The dispute on ${contract.contractCode} was resolved by an administrator.`);
    }
    return { success: true, status: newState, refundedToClient: refundable, paidToBeneficiary: paidOut };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. QUERIES: REAL-TIME ESCROW TRACKING & ADMIN TELEMETRY
// ═══════════════════════════════════════════════════════════════════════

export const getMyRealEstateEscrows = query({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await resolveCallerUser(ctx, args.userId, args.sessionToken);

    const asClient = await ctx.db.query("re_escrow_contracts").withIndex("by_client", (q: any) => q.eq("clientId", userId)).order("desc").take(200);
    const asBeneficiary = await ctx.db.query("re_escrow_contracts").withIndex("by_beneficiary", (q: any) => q.eq("beneficiaryId", userId)).order("desc").take(200);
    // Deals where the caller is the owner-authorised listing agent (their commission is part of it).
    const asAgent = await ctx.db.query("re_escrow_contracts").withIndex("by_agentId", (q: any) => q.eq("agentId", userId)).order("desc").take(200);
    const contractMap = new Map();
    for (const c of [...asClient, ...asBeneficiary, ...asAgent]) contractMap.set(c._id, c);
    const allContracts = Array.from(contractMap.values()).sort((a, b) => b.createdAt - a.createdAt);

    const hydratedContracts = [];
    for (const c of allContracts) {
      const prop: any = await ctx.db.get(c.propertyListingId);
      hydratedContracts.push({
        ...c,
        propertyTitle: prop?.title ?? "Real Estate Property",
        propertyCategory: prop?.category ?? "residential",
        propertyCity: prop ? publicLocation(prop.city, prop.district) : "Sierra Leone",
        propertyImage: prop?.imageUrls?.[0] ?? "",
        isOwner: c.beneficiaryId === userId,
        // the authorised listing agent on someone else's listing (agentId is the owner when no agent)
        isAgent: c.agentId === userId && c.beneficiaryId !== userId,
      });
    }

    const passesAsClient = await ctx.db.query("re_inspection_passes").withIndex("by_client", (q: any) => q.eq("clientId", userId)).order("desc").take(200);
    const passesAsAgent = await ctx.db.query("re_inspection_passes").withIndex("by_agent", (q: any) => q.eq("agentId", userId)).order("desc").take(200);
    const passMap = new Map();
    for (const p of [...passesAsClient, ...passesAsAgent]) passMap.set(p._id, p);
    const allPasses = Array.from(passMap.values()).sort((a, b) => b.createdAt - a.createdAt);

    const hydratedPasses = [];
    for (const p of allPasses) {
      const prop: any = await ctx.db.get(p.propertyListingId);
      const isAgent = p.agentId === userId;
      // The verification secrets belong to the client: the agent must not see them.
      const { otpCode, qrHash, ...rest } = p;
      // The agent running the tour sees the client's display name only (no contact details).
      const client: any = isAgent ? await ctx.db.get(p.clientId) : null;
      hydratedPasses.push({
        ...rest,
        ...(isAgent ? {} : { otpCode, qrHash }),
        propertyTitle: prop?.title ?? "Property Tour",
        propertyImage: prop?.imageUrls?.[0] ?? "",
        ...(isAgent ? { clientName: client?.name ?? "Client" } : {}),
        isAgent,
      });
    }

    return { contracts: hydratedContracts, inspectionPasses: hydratedPasses };
  },
});

export const getRealEstateEscrowById = query({
  args: { contractId: v.id("re_escrow_contracts"), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const contract = await ctx.db.get(args.contractId);
    if (!contract) return null;
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [contract.clientId, contract.beneficiaryId, contract.agentId]);

    const property: any = await ctx.db.get(contract.propertyListingId);
    const client = await ctx.db.get(contract.clientId);
    const beneficiary = await ctx.db.get(contract.beneficiaryId);
    const isOwnerOrAdmin = who.isAdmin || String(who.userId) === String(contract.beneficiaryId);

    const milestones = await ctx.db.query("re_escrow_milestones").withIndex("by_contract", (q: any) => q.eq("contractId", contract._id)).collect();
    const caution = await ctx.db.query("re_caution_deposits").withIndex("by_contract", (q: any) => q.eq("contractId", contract._id)).first();
    const disputes = await ctx.db.query("re_escrow_disputes").withIndex("by_contract", (q: any) => q.eq("contractId", contract._id)).collect();

    // Privacy: the client sees only the broad public location. The street address, coordinates and
    // contact phones are never returned to the other party (Vektolux coordinates handovers).
    const safeProperty = property
      ? isOwnerOrAdmin
        ? property
        : {
            _id: property._id,
            title: property.title,
            category: property.category,
            price: property.price,
            currency: property.currency,
            imageUrls: property.imageUrls,
            city: publicLocation(property.city, property.district),
            country: property.country,
          }
      : null;

    return {
      contract,
      property: safeProperty,
      clientName: client?.name ?? "Client",
      beneficiaryName: beneficiary?.name ?? "Property Owner",
      milestones: milestones.sort((a, b) => a.milestoneIndex - b.milestoneIndex),
      cautionDeposit: caution,
      disputes,
    };
  },
});

export const getAdminRealEstateEscrowSummary = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const contracts = await ctx.db.query("re_escrow_contracts").collect();
    const passes = await ctx.db.query("re_inspection_passes").collect();
    const disputes = await ctx.db.query("re_escrow_disputes").collect();
    const cautions = await ctx.db.query("re_caution_deposits").collect();

    let totalInEscrow = 0;
    let totalSettledVolume = 0;
    let activeShortStays = 0;
    let activeLongLeases = 0;
    let activeLandMilestones = 0;
    let cautionDepositsHeld = 0;

    for (const c of contracts) {
      if (["FUNDS_LOCKED", "CHECKED_IN", "MILESTONE_VERIFIED", "UNDER_ARBITRATION"].includes(c.currentState)) {
        totalInEscrow += heldRemaining(c);
        if (c.contractType === "SHORT_STAY_BOOKING") activeShortStays++;
        if (c.contractType === "LONG_TERM_LEASE") activeLongLeases++;
        if (c.contractType === "LAND_PURCHASE_MILESTONE") activeLandMilestones++;
      } else if (c.currentState === "FULLY_SETTLED") {
        totalSettledVolume += c.grossAmount;
      }
    }
    for (const d of cautions) {
      if (d.status === "LOCKED" || d.status === "IN_DISPUTE") cautionDepositsHeld += d.heldAmount;
    }

    return {
      totalContracts: contracts.length,
      totalInspectionPasses: passes.length,
      totalInEscrow: round2(totalInEscrow),
      totalSettledVolume,
      cautionDepositsHeld,
      activeShortStays,
      activeLongLeases,
      activeLandMilestones,
      activeDisputesCount: disputes.filter((d) => d.status === "OPENED" || d.status === "EVIDENCE_SUBMITTED").length,
      recentContracts: contracts.slice(-50).reverse(),
    };
  },
});
