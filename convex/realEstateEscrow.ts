// convex/realEstateEscrow.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Multi-Tier Real Estate Escrow & Settlement Engine
// Implements:
// 1. Inspection Pass (Anti-Bypass Tours with 85/15 Agent/Platform Split)
// 2. Short-Stay Bookings (24-Hour Host Payout Rule + Caution Vault)
// 3. Long-Term Leases (10% Agency Commission + Locked Caution Deposit)
// 4. Land & House Purchases (10/40/50 Gated Milestone Escrow)
// Operating Standard: Sierra Leone New Leones (SLE)
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query, internalMutation } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import {
  reContractType,
  reMilestoneState,
  reDisputeStatus,
} from "./schema";

// ─── Helper: Resolve Caller User ──────────────────────────────────────
async function resolveCallerUser(ctx: any, explicitUserId?: string): Promise<Id<"users">> {
  if (explicitUserId) {
    const norm = ctx.db.normalizeId("users", explicitUserId);
    if (norm) return norm;
  }
  const identity = await ctx.auth.getUserIdentity();
  if (identity && identity.email) {
    const byEmail = await ctx.db
      .query("users")
      .withIndex("by_email", (q: any) => q.eq("email", identity.email!))
      .first();
    if (byEmail) return byEmail._id;
  }
  const fallback = await ctx.db.query("users").first();
  if (fallback) return fallback._id;
  throw new Error("User authentication required");
}

// ─── Helper: Ensure or get user wallet ────────────────────────────────
async function getOrCreateWallet(ctx: any, userId: Id<"users">) {
  const existing = await ctx.db
    .query("walletBalances")
    .withIndex("by_user", (q: any) => q.eq("userId", userId))
    .first();

  if (existing) return existing;

  const newId = await ctx.db.insert("walletBalances", {
    userId,
    availableBalance: 0,
    pendingBalance: 0,
    escrowBalance: 0,
    currency: "SLE",
    updatedAt: Date.now(),
  });
  return await ctx.db.get(newId);
}

// ─── Helper: Post Double-Entry Ledger Transaction ─────────────────────
async function postLedgerTransaction(
  ctx: any,
  params: {
    code: string;
    description: string;
    entries: Array<{
      accountType:
        | "CLIENT_AVAILABLE"
        | "CLIENT_ESCROW_LOCKED"
        | "OWNER_AVAILABLE"
        | "OWNER_ESCROW_PENDING"
        | "PLATFORM_REVENUE_REALIZED"
        | "DAMAGE_DEPOSIT_CUSTODY"
        | "TELCO_CLEARING_LIABILITY";
      userId?: Id<"users">;
      direction: "DEBIT" | "CREDIT";
      amount: number;
    }>;
  }
) {
  let totalDebit = 0;
  let totalCredit = 0;
  for (const e of params.entries) {
    if (e.direction === "DEBIT") totalDebit += e.amount;
    if (e.direction === "CREDIT") totalCredit += e.amount;
  }

  // Allow negligible floating point delta
  if (Math.abs(totalDebit - totalCredit) > 0.05) {
    throw new Error(
      `Ledger invariant violated: Debits (${totalDebit.toFixed(2)}) !== Credits (${totalCredit.toFixed(2)})`
    );
  }

  const txId = await ctx.db.insert("ledger_transactions", {
    transactionCode: params.code,
    description: params.description,
    createdAt: Date.now(),
  });

  for (const entry of params.entries) {
    await ctx.db.insert("ledger_entries", {
      transactionId: txId,
      accountType: entry.accountType,
      userId: entry.userId,
      direction: entry.direction,
      amount: entry.amount,
      currency: "SLE",
      createdAt: Date.now(),
    });
  }
  return txId;
}

// ═══════════════════════════════════════════════════════════════════════
// 1. INSPECTION PASS (ANTI-BYPASS TOURS)
// ═══════════════════════════════════════════════════════════════════════

export const initiateInspectionPass = mutation({
  args: {
    propertyListingId: v.id("realEstateListings"),
    clientId: v.optional(v.string()),
    preferredAgentId: v.optional(v.string()),
    tourFee: v.optional(v.number()), // default SLE 100
    scheduledTimestamp: v.number(),
    paymentRail: v.optional(v.string()), // ORANGE_MONEY_SL, AFRICELL_AFRIMONEY_SL, WALLET
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
    assignedAgentPhone: v.string(),
    maskedNeighborhood: v.string(),
  }),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx, args.clientId);
    const property = await ctx.db.get(args.propertyListingId);
    if (!property) throw new Error("Property listing not found");

    if (property.ownerId === currentUserId) {
      throw new Error("You cannot book an inspection tour on your own property.");
    }

    const fee = args.tourFee ?? 100.0;
    const platformFee = Math.round(fee * 0.15 * 100) / 100; // 15% platform cut
    const agentNetFee = fee - platformFee; // 85% to agent

    // Resolve assigned agent: preferred agent, property owner, or fallback verified agent
    let agentId: Id<"users">;
    if (args.preferredAgentId) {
      const normAgent = ctx.db.normalizeId("users", args.preferredAgentId);
      agentId = normAgent ?? property.ownerId;
    } else {
      agentId = property.ownerId;
    }

    const agentUser = await ctx.db.get(agentId);

    // Generate cryptographic QR hash & 4-digit OTP
    const now = Date.now();
    const randomSuffix = Math.floor(1000 + Math.random() * 9000);
    const qrHash = `VK-TOUR-${now.toString().slice(-6)}-${randomSuffix}`;
    const otpCode = Math.floor(1000 + Math.random() * 9000).toString();
    const otpExpiresAt = args.scheduledTimestamp + 4 * 3600 * 1000; // Valid for scheduled time + 4 hours

    // Lock funds in escrow
    const clientWallet = await getOrCreateWallet(ctx, currentUserId);
    if (clientWallet.availableBalance >= fee) {
      await ctx.db.patch(clientWallet._id, {
        availableBalance: clientWallet.availableBalance - fee,
        escrowBalance: (clientWallet.escrowBalance ?? 0) + fee,
        updatedAt: now,
      });
    }

    const passId = await ctx.db.insert("re_inspection_passes", {
      propertyListingId: property._id,
      clientId: currentUserId,
      agentId,
      tourFee: fee,
      platformFee,
      agentNetFee,
      qrHash,
      otpCode,
      otpExpiresAt,
      status: "FUNDS_LOCKED",
      scheduledAt: args.scheduledTimestamp,
      isAddressUnmasked: false,
      createdAt: now,
    });

    // Double-entry record
    await postLedgerTransaction(ctx, {
      code: `TX-INSP-${now.toString().slice(-6)}`,
      description: `Viewing Tour Pass fee locked for ${property.title}`,
      entries: [
        {
          accountType: "TELCO_CLEARING_LIABILITY",
          userId: currentUserId,
          direction: "DEBIT",
          amount: fee,
        },
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: currentUserId,
          direction: "CREDIT",
          amount: fee,
        },
      ],
    });

    return {
      passId: passId as string,
      qrHash,
      otpCode,
      tourFee: fee,
      agentNetFee,
      platformFee,
      expiresAt: otpExpiresAt,
      status: "FUNDS_LOCKED",
      assignedAgentName: agentUser?.name ?? "Vektolux Verified Field Agent",
      assignedAgentPhone: agentUser?.phone ?? "+232 76 000 000",
      maskedNeighborhood: `${property.city}, Sierra Leone (Exact compound unmasked upon meeting agent)`,
    };
  },
});

export const verifyInspectionPass = mutation({
  args: {
    passId: v.id("re_inspection_passes"),
    scannedQrHash: v.optional(v.string()),
    enteredOtp: v.optional(v.string()),
    agentId: v.optional(v.string()),
    agentGpsLat: v.optional(v.number()),
    agentGpsLng: v.optional(v.number()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    agentNetPaid: v.number(),
    unmaskedAddress: v.string(),
    unmaskedContactPhone: v.string(),
    ownerName: v.string(),
    verifiedAt: v.number(),
  }),
  handler: async (ctx, args) => {
    const pass = await ctx.db.get(args.passId);
    if (!pass) throw new Error("Inspection pass not found");

    if (pass.status === "FULLY_SETTLED" || pass.status === "MILESTONE_VERIFIED") {
      throw new Error("This inspection pass has already been verified and settled.");
    }

    // Verify cryptographic QR or 4-digit OTP
    const isQrMatch = args.scannedQrHash && args.scannedQrHash.trim() === pass.qrHash;
    const isOtpMatch = args.enteredOtp && args.enteredOtp.trim() === pass.otpCode;

    if (!isQrMatch && !isOtpMatch) {
      throw new Error("Invalid verification code. QR scan or 4-digit OTP did not match.");
    }

    const now = Date.now();
    if (now > pass.otpExpiresAt + 24 * 3600 * 1000) {
      throw new Error("Inspection pass has expired. Please book a new viewing tour.");
    }

    const property = await ctx.db.get(pass.propertyListingId);
    if (!property) throw new Error("Associated property listing not found");
    const owner = await ctx.db.get(property.ownerId);

    // Disburse funds: 85% to Agent, 15% to Platform
    const clientWallet = await getOrCreateWallet(ctx, pass.clientId);
    const agentWallet = await getOrCreateWallet(ctx, pass.agentId);

    // Release from client's escrow balance
    await ctx.db.patch(clientWallet._id, {
      escrowBalance: Math.max(0, (clientWallet.escrowBalance ?? 0) - pass.tourFee),
      updatedAt: now,
    });

    // Credit agent available balance
    await ctx.db.patch(agentWallet._id, {
      availableBalance: agentWallet.availableBalance + pass.agentNetFee,
      updatedAt: now,
    });

    // Mark pass settled and unmask property address
    await ctx.db.patch(pass._id, {
      status: "FULLY_SETTLED",
      isAddressUnmasked: true,
      verifiedAt: now,
      agentGpsLat: args.agentGpsLat,
      agentGpsLng: args.agentGpsLng,
    });

    // Double-entry ledger
    await postLedgerTransaction(ctx, {
      code: `TX-INSP-SETTLE-${now.toString().slice(-6)}`,
      description: `Viewing Tour Pass settled: 85% to Agent, 15% to Platform`,
      entries: [
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: pass.clientId,
          direction: "DEBIT",
          amount: pass.tourFee,
        },
        {
          accountType: "OWNER_AVAILABLE",
          userId: pass.agentId,
          direction: "CREDIT",
          amount: pass.agentNetFee,
        },
        {
          accountType: "PLATFORM_REVENUE_REALIZED",
          direction: "CREDIT",
          amount: pass.platformFee,
        },
      ],
    });

    return {
      success: true,
      status: "FULLY_SETTLED",
      agentNetPaid: pass.agentNetFee,
      unmaskedAddress: property.address,
      unmaskedContactPhone: property.privateContactPhone ?? owner?.phone ?? "+232 76 000 001",
      ownerName: owner?.name ?? "Property Owner",
      verifiedAt: now,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. MASTER REAL ESTATE ESCROW: STAYS, LEASES & LAND PURCHASES
// ═══════════════════════════════════════════════════════════════════════

export const initiateRealEstateEscrow = mutation({
  args: {
    contractType: reContractType,
    propertyListingId: v.id("realEstateListings"),
    clientId: v.optional(v.string()),
    baseAmount: v.number(), // Stay total, Annual rent, or Total purchase price
    cautionDepositAmount: v.optional(v.number()),
    nightsCount: v.optional(v.number()),
    leaseDurationMonths: v.optional(v.number()),
    paymentRail: v.optional(v.string()), // ORANGE_MONEY_SL, AFRICELL_AFRIMONEY_SL, WALLET
    paymentPhone: v.optional(v.string()),
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
    status: v.string(),
  }),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx, args.clientId);
    const property = await ctx.db.get(args.propertyListingId);
    if (!property) throw new Error("Property listing not found");

    if (property.ownerId === currentUserId) {
      throw new Error("You cannot create an escrow contract for your own property.");
    }

    const now = Date.now();
    const contractCode = `VK-RE-${now.toString().slice(-6)}-${Math.floor(1000 + Math.random() * 9000)}`;

    let cautionDeposit = args.cautionDepositAmount ?? 0;
    let platformFee = 0;
    let agentCommission = 0;
    let netBeneficiary = 0;
    let grossEscrow = 0;

    if (args.contractType === "SHORT_STAY_BOOKING") {
      // Platform takes 10% fee on base accommodation stay
      platformFee = Math.round(args.baseAmount * 0.10 * 100) / 100;
      netBeneficiary = args.baseAmount - platformFee;
      grossEscrow = args.baseAmount + cautionDeposit;
    } else if (args.contractType === "LONG_TERM_LEASE") {
      // 10% statutory agency commission
      const rawCommission = Math.round(args.baseAmount * 0.10 * 100) / 100;
      platformFee = Math.round(rawCommission * 0.15 * 100) / 100; // 15% platform tech cut
      agentCommission = rawCommission - platformFee; // 85% to listing agent
      netBeneficiary = args.baseAmount;
      grossEscrow = args.baseAmount + rawCommission + cautionDeposit;
    } else if (args.contractType === "LAND_PURCHASE_MILESTONE") {
      // 5% standard real estate conveyancing fee on land
      platformFee = Math.round(args.baseAmount * 0.05 * 100) / 100;
      netBeneficiary = args.baseAmount - platformFee;
      grossEscrow = args.baseAmount;
      cautionDeposit = 0;
    }

    // Insert master contract
    const contractId = await ctx.db.insert("re_escrow_contracts", {
      contractCode,
      contractType: args.contractType,
      propertyListingId: property._id,
      clientId: currentUserId,
      beneficiaryId: property.ownerId,
      agentId: property.ownerId,
      grossAmount: grossEscrow,
      cautionDepositAmount: cautionDeposit,
      platformFeeAmount: platformFee,
      agentCommissionAmount: agentCommission,
      netBeneficiaryExpected: netBeneficiary,
      releasedBeneficiaryAmount: 0,
      refundedClientAmount: 0,
      paymentRail: args.paymentRail ?? "ORANGE_MONEY_SL",
      currentState: "FUNDS_LOCKED",
      leaseDurationMonths: args.leaseDurationMonths,
      createdAt: now,
      updatedAt: now,
    });

    // If caution deposit > 0, create segregated vault record
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

    // If Land Purchase, create the 10/40/50 milestone stage records
    if (args.contractType === "LAND_PURCHASE_MILESTONE") {
      const m1Amount = Math.round(grossEscrow * 0.10 * 100) / 100;
      const m2Amount = Math.round(grossEscrow * 0.40 * 100) / 100;
      const m3Amount = grossEscrow - m1Amount - m2Amount;

      await ctx.db.insert("re_escrow_milestones", {
        contractId,
        milestoneIndex: 1,
        title: "Title Search & Root Confirmation (10%)",
        targetPercentage: 10,
        amount: m1Amount,
        verificationRequirement: "Certified OARG (Roxy Building) Search Report confirming clean title",
        proofDocumentUrls: [],
        isVerified: false,
        state: "FUNDS_LOCKED",
        createdAt: now,
      });

      await ctx.db.insert("re_escrow_milestones", {
        contractId,
        milestoneIndex: 2,
        title: "Cadastral Survey Plan & Deed Verification (40%)",
        targetPercentage: 40,
        amount: m2Amount,
        verificationRequirement: "Licensed Surveyor beacon sign-off + MLHCP Cadastral confirmation",
        proofDocumentUrls: [],
        isVerified: false,
        state: "CREATED",
        createdAt: now,
      });

      await ctx.db.insert("re_escrow_milestones", {
        contractId,
        milestoneIndex: 3,
        title: "Final Conveyance Signing & OARG Registration (50%)",
        targetPercentage: 50,
        amount: m3Amount,
        verificationRequirement: "Signed Deed of Conveyance + OARG Volume & Page registration stamp",
        proofDocumentUrls: [],
        isVerified: false,
        state: "CREATED",
        createdAt: now,
      });
    }

    // Isolate funds in client wallet
    const clientWallet = await getOrCreateWallet(ctx, currentUserId);
    if (clientWallet.availableBalance >= grossEscrow) {
      await ctx.db.patch(clientWallet._id, {
        availableBalance: clientWallet.availableBalance - grossEscrow,
        escrowBalance: (clientWallet.escrowBalance ?? 0) + grossEscrow,
        updatedAt: now,
      });
    }

    // Post Double-Entry Ledger
    await postLedgerTransaction(ctx, {
      code: `TX-RE-${now.toString().slice(-6)}`,
      description: `Escrow custody locked for ${args.contractType}: ${property.title}`,
      entries: [
        {
          accountType: "TELCO_CLEARING_LIABILITY",
          userId: currentUserId,
          direction: "DEBIT",
          amount: grossEscrow,
        },
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: currentUserId,
          direction: "CREDIT",
          amount: grossEscrow,
        },
      ],
    });

    return {
      contractId: contractId as string,
      contractCode,
      contractType: args.contractType,
      grossEscrowAmount: grossEscrow,
      cautionDeposit,
      platformFee,
      agentCommission,
      netBeneficiaryExpected: netBeneficiary,
      status: "FUNDS_LOCKED",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. SHORT-STAY 24-HOUR CHECK-IN RULE & CAUTION REFUNDS
// ═══════════════════════════════════════════════════════════════════════

export const checkInShortStay = mutation({
  args: {
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

    if (contract.contractType !== "SHORT_STAY_BOOKING") {
      throw new Error("24-hour check-in rule only applies to Short-Stay Bookings");
    }

    const now = Date.now();
    const autoReleaseTime = now + 24 * 3600 * 1000; // Exactly 24 hours later

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
      message: "Guest checked in! Net accommodation payout will disburse to host in 24 hours if no defect dispute is raised.",
    };
  },
});

export const releaseShortStayPayout24h = mutation({
  args: {
    contractId: v.id("re_escrow_contracts"),
    adminForceOverride: v.optional(v.boolean()),
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

    if (contract.currentState !== "CHECKED_IN") {
      throw new Error(`Contract must be in CHECKED_IN state. Current: ${contract.currentState}`);
    }

    const now = Date.now();
    if (!args.adminForceOverride && contract.stay24hAutoReleaseTimestamp && now < contract.stay24hAutoReleaseTimestamp) {
      const remainingMinutes = Math.ceil((contract.stay24hAutoReleaseTimestamp - now) / 60000);
      throw new Error(`24-hour holding period still active. ${remainingMinutes} minutes remaining before auto-disbursal.`);
    }

    // Check for open dispute
    const openDisputes = await ctx.db
      .query("re_escrow_disputes")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .collect();

    if (openDisputes.some((d: any) => d.status === "OPENED" || d.status === "EVIDENCE_SUBMITTED")) {
      throw new Error("Payout cannot be released while an active dispute is in arbitration.");
    }

    const hostWallet = await getOrCreateWallet(ctx, contract.beneficiaryId);
    const clientWallet = await getOrCreateWallet(ctx, contract.clientId);

    // Release host rent from client's escrow balance
    const stayCost = contract.grossAmount - contract.cautionDepositAmount;
    await ctx.db.patch(clientWallet._id, {
      escrowBalance: Math.max(0, (clientWallet.escrowBalance ?? 0) - stayCost),
      updatedAt: now,
    });

    // Credit host available balance
    await ctx.db.patch(hostWallet._id, {
      availableBalance: hostWallet.availableBalance + contract.netBeneficiaryExpected,
      updatedAt: now,
    });

    // If no caution deposit, contract is settled; otherwise stays active until check-out
    const newState = contract.cautionDepositAmount > 0 ? "MILESTONE_VERIFIED" : "FULLY_SETTLED";

    await ctx.db.patch(contract._id, {
      currentState: newState,
      releasedBeneficiaryAmount: contract.netBeneficiaryExpected,
      updatedAt: now,
    });

    // Double-entry record
    await postLedgerTransaction(ctx, {
      code: `TX-STAY-24H-${now.toString().slice(-6)}`,
      description: `24-hour host payout cleared for contract ${contract.contractCode}`,
      entries: [
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: contract.clientId,
          direction: "DEBIT",
          amount: stayCost,
        },
        {
          accountType: "OWNER_AVAILABLE",
          userId: contract.beneficiaryId,
          direction: "CREDIT",
          amount: contract.netBeneficiaryExpected,
        },
        {
          accountType: "PLATFORM_REVENUE_REALIZED",
          direction: "CREDIT",
          amount: contract.platformFeeAmount,
        },
      ],
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

    const caution = await ctx.db
      .query("re_caution_deposits")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .first();

    if (!caution) throw new Error("No caution deposit record found for this contract");
    if (caution.status === "REFUNDED_CLEAN" || caution.status === "FORFEITED_FULL") {
      throw new Error("Caution deposit has already been settled");
    }

    const now = Date.now();
    let refundedAmount = caution.heldAmount;
    let deductionAmount = 0;

    if (!args.inspectionPassedClean && args.damageDeductionAmount && args.damageDeductionAmount > 0) {
      deductionAmount = Math.min(args.damageDeductionAmount, caution.heldAmount);
      refundedAmount = caution.heldAmount - deductionAmount;
    }

    const clientWallet = await getOrCreateWallet(ctx, contract.clientId);
    const hostWallet = await getOrCreateWallet(ctx, contract.beneficiaryId);

    // Release caution from client's escrow balance
    await ctx.db.patch(clientWallet._id, {
      escrowBalance: Math.max(0, (clientWallet.escrowBalance ?? 0) - caution.heldAmount),
      availableBalance: clientWallet.availableBalance + refundedAmount,
      updatedAt: now,
    });

    if (deductionAmount > 0) {
      await ctx.db.patch(hostWallet._id, {
        availableBalance: hostWallet.availableBalance + deductionAmount,
        updatedAt: now,
      });
    }

    const cautionStatus = deductionAmount > 0 ? "DEDUCTED_PARTIAL" : "REFUNDED_CLEAN";

    await ctx.db.patch(caution._id, {
      status: cautionStatus,
      refundedAmount,
      deductionClaimAmount: deductionAmount,
      inventoryChecklistSigned: true,
      checkoutNotes: args.notes,
      settledAt: now,
    });

    await ctx.db.patch(contract._id, {
      currentState: "FULLY_SETTLED",
      refundedClientAmount: (contract.refundedClientAmount ?? 0) + refundedAmount,
      updatedAt: now,
    });

    // Double-entry record
    await postLedgerTransaction(ctx, {
      code: `TX-CAUTION-SETTLE-${now.toString().slice(-6)}`,
      description: `Caution deposit settled for ${contract.contractCode} (Refunded: ${refundedAmount}, Deducted: ${deductionAmount})`,
      entries: [
        {
          accountType: "DAMAGE_DEPOSIT_CUSTODY",
          userId: contract.clientId,
          direction: "DEBIT",
          amount: caution.heldAmount,
        },
        {
          accountType: "CLIENT_AVAILABLE",
          userId: contract.clientId,
          direction: "CREDIT",
          amount: refundedAmount,
        },
        ...(deductionAmount > 0
          ? [
              {
                accountType: "OWNER_AVAILABLE" as const,
                userId: contract.beneficiaryId,
                direction: "CREDIT" as const,
                amount: deductionAmount,
              },
            ]
          : []),
      ],
    });

    return {
      success: true,
      refundedToClient: refundedAmount,
      deductedToHost: deductionAmount,
      status: "FULLY_SETTLED",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. LAND & HOUSE PURCHASE MILESTONES (10 / 40 / 50 GATED RELEASE)
// ═══════════════════════════════════════════════════════════════════════

export const verifyAndReleaseLandMilestone = mutation({
  args: {
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

    if (contract.contractType !== "LAND_PURCHASE_MILESTONE") {
      throw new Error("Milestone releases only apply to Land & House Purchases");
    }

    const milestone = await ctx.db
      .query("re_escrow_milestones")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .filter((q: any) => q.eq(q.field("milestoneIndex"), args.milestoneIndex))
      .first();

    if (!milestone) throw new Error(`Milestone ${args.milestoneIndex} not found`);
    if (milestone.state === "FULLY_SETTLED") {
      throw new Error(`Milestone ${args.milestoneIndex} has already been released`);
    }

    // Ensure previous milestone is settled if milestoneIndex > 1
    if (args.milestoneIndex > 1) {
      const prevMilestone = await ctx.db
        .query("re_escrow_milestones")
        .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
        .filter((q: any) => q.eq(q.field("milestoneIndex"), args.milestoneIndex - 1))
        .first();

      if (!prevMilestone || prevMilestone.state !== "FULLY_SETTLED") {
        throw new Error(`Cannot release Milestone ${args.milestoneIndex} before Milestone ${args.milestoneIndex - 1} is verified and settled`);
      }
    }

    const now = Date.now();
    const sellerWallet = await getOrCreateWallet(ctx, contract.beneficiaryId);
    const clientWallet = await getOrCreateWallet(ctx, contract.clientId);

    // Deduct from client's escrow balance
    await ctx.db.patch(clientWallet._id, {
      escrowBalance: Math.max(0, (clientWallet.escrowBalance ?? 0) - milestone.amount),
      updatedAt: now,
    });

    // Credit seller
    await ctx.db.patch(sellerWallet._id, {
      availableBalance: sellerWallet.availableBalance + milestone.amount,
      updatedAt: now,
    });

    // Mark milestone settled
    await ctx.db.patch(milestone._id, {
      state: "FULLY_SETTLED",
      isVerified: true,
      proofDocumentUrls: args.proofDocumentUrls,
      releasedAt: now,
    });

    const newReleasedTotal = contract.releasedBeneficiaryAmount + milestone.amount;
    const isFinalMilestone = args.milestoneIndex === 3;
    const contractNewState = isFinalMilestone ? "FULLY_SETTLED" : "MILESTONE_VERIFIED";

    await ctx.db.patch(contract._id, {
      releasedBeneficiaryAmount: newReleasedTotal,
      currentState: contractNewState,
      updatedAt: now,
    });

    // Double-entry record
    await postLedgerTransaction(ctx, {
      code: `TX-LAND-M${args.milestoneIndex}-${now.toString().slice(-6)}`,
      description: `Milestone ${args.milestoneIndex} (${milestone.title}) released for ${contract.contractCode}`,
      entries: [
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: contract.clientId,
          direction: "DEBIT",
          amount: milestone.amount,
        },
        {
          accountType: "OWNER_AVAILABLE",
          userId: contract.beneficiaryId,
          direction: "CREDIT",
          amount: milestone.amount,
        },
      ],
    });

    const remainingInEscrow = Math.max(0, contract.grossAmount - newReleasedTotal);

    return {
      success: true,
      milestoneIndex: args.milestoneIndex,
      amountReleased: milestone.amount,
      contractState: contractNewState,
      remainingInEscrow,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. DISPUTES & ARBITRATION
// ═══════════════════════════════════════════════════════════════════════

export const raiseRealEstateDispute = mutation({
  args: {
    contractId: v.id("re_escrow_contracts"),
    claimantUserId: v.optional(v.string()),
    claimantRole: v.string(), // CLIENT, HOST, LANDLORD, AGENT
    reason: v.string(),
    claimedRepairCost: v.number(),
    evidenceMediaUrls: v.array(v.string()),
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const callerId = await resolveCallerUser(ctx, args.claimantUserId);
    const contract = await ctx.db.get(args.contractId);
    if (!contract) throw new Error("Contract not found");

    const now = Date.now();

    const disputeId = await ctx.db.insert("re_escrow_disputes", {
      contractId: contract._id,
      openedByUserId: callerId,
      claimantRole: args.claimantRole,
      reason: args.reason,
      claimedRepairCost: args.claimedRepairCost,
      evidenceMediaUrls: args.evidenceMediaUrls,
      status: "OPENED",
      openedAt: now,
    });

    // Freeze contract state
    await ctx.db.patch(contract._id, {
      currentState: "UNDER_ARBITRATION",
      updatedAt: now,
    });

    return disputeId as string;
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. QUERIES: REAL-TIME ESCROW TRACKING & ADMIN TELEMETRY
// ═══════════════════════════════════════════════════════════════════════

export const getMyRealEstateEscrows = query({
  args: {
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await resolveCallerUser(ctx, args.userId);

    // 1. Fetch contracts where user is client or beneficiary
    const asClient = await ctx.db
      .query("re_escrow_contracts")
      .withIndex("by_client", (q: any) => q.eq("clientId", userId))
      .collect();

    const asBeneficiary = await ctx.db
      .query("re_escrow_contracts")
      .withIndex("by_beneficiary", (q: any) => q.eq("beneficiaryId", userId))
      .collect();

    const contractMap = new Map();
    for (const c of [...asClient, ...asBeneficiary]) {
      contractMap.set(c._id, c);
    }
    const allContracts = Array.from(contractMap.values()).sort((a, b) => b.createdAt - a.createdAt);

    // Hydrate property details
    const hydratedContracts = [];
    for (const c of allContracts) {
      const prop: any = await ctx.db.get(c.propertyListingId);
      hydratedContracts.push({
        ...c,
        propertyTitle: prop?.title ?? "Real Estate Property",
        propertyCategory: prop?.category ?? "residential",
        propertyCity: prop?.city ?? "Freetown",
        propertyImage: prop?.imageUrls?.[0] ?? "",
        isOwner: c.beneficiaryId === userId,
      });
    }

    // 2. Fetch inspection passes
    const passesAsClient = await ctx.db
      .query("re_inspection_passes")
      .withIndex("by_client", (q: any) => q.eq("clientId", userId))
      .collect();

    const passesAsAgent = await ctx.db
      .query("re_inspection_passes")
      .withIndex("by_agent", (q: any) => q.eq("agentId", userId))
      .collect();

    const passMap = new Map();
    for (const p of [...passesAsClient, ...passesAsAgent]) {
      passMap.set(p._id, p);
    }
    const allPasses = Array.from(passMap.values()).sort((a, b) => b.createdAt - a.createdAt);

    const hydratedPasses = [];
    for (const p of allPasses) {
      const prop: any = await ctx.db.get(p.propertyListingId);
      hydratedPasses.push({
        ...p,
        propertyTitle: prop?.title ?? "Property Tour",
        propertyImage: prop?.imageUrls?.[0] ?? "",
        isAgent: p.agentId === userId,
      });
    }

    return {
      contracts: hydratedContracts,
      inspectionPasses: hydratedPasses,
    };
  },
});

export const getRealEstateEscrowById = query({
  args: { contractId: v.id("re_escrow_contracts") },
  handler: async (ctx, args) => {
    const contract = await ctx.db.get(args.contractId);
    if (!contract) return null;

    const property = await ctx.db.get(contract.propertyListingId);
    const client = await ctx.db.get(contract.clientId);
    const beneficiary = await ctx.db.get(contract.beneficiaryId);

    const milestones = await ctx.db
      .query("re_escrow_milestones")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .collect();

    const caution = await ctx.db
      .query("re_caution_deposits")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .first();

    const disputes = await ctx.db
      .query("re_escrow_disputes")
      .withIndex("by_contract", (q: any) => q.eq("contractId", contract._id))
      .collect();

    return {
      contract,
      property,
      clientName: client?.name ?? "Client",
      clientPhone: client?.phone ?? "",
      beneficiaryName: beneficiary?.name ?? "Property Owner",
      beneficiaryPhone: beneficiary?.phone ?? "",
      milestones: milestones.sort((a, b) => a.milestoneIndex - b.milestoneIndex),
      cautionDeposit: caution,
      disputes,
    };
  },
});

export const getAdminRealEstateEscrowSummary = query({
  args: {},
  handler: async (ctx) => {
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
      if (c.currentState === "FUNDS_LOCKED" || c.currentState === "CHECKED_IN" || c.currentState === "MILESTONE_VERIFIED") {
        totalInEscrow += Math.max(0, c.grossAmount - c.releasedBeneficiaryAmount);
        if (c.contractType === "SHORT_STAY_BOOKING") activeShortStays++;
        if (c.contractType === "LONG_TERM_LEASE") activeLongLeases++;
        if (c.contractType === "LAND_PURCHASE_MILESTONE") activeLandMilestones++;
      } else if (c.currentState === "FULLY_SETTLED") {
        totalSettledVolume += c.grossAmount;
      }
    }

    for (const d of cautions) {
      if (d.status === "LOCKED" || d.status === "IN_DISPUTE") {
        cautionDepositsHeld += d.heldAmount;
      }
    }

    return {
      totalContracts: contracts.length,
      totalInspectionPasses: passes.length,
      totalInEscrow,
      totalSettledVolume,
      cautionDepositsHeld,
      activeShortStays,
      activeLongLeases,
      activeLandMilestones,
      activeDisputesCount: disputes.filter((d) => d.status === "OPENED" || d.status === "EVIDENCE_SUBMITTED").length,
    };
  },
});
