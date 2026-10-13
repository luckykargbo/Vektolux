// test-support/legacyRentalFixture.ts
// ═══════════════════════════════════════════════════════════════════════
// TEST-ONLY. New vehicle-rental orders can no longer be created through escrow.initiateEscrowOrder
// (it refuses VEHICLE_RENTAL). Tests that must exercise the lifecycle of a HISTORICAL rental order
// (funding, handoff, return, dispute, expiry, late payment, fee snapshots) seed one directly, with
// exactly the amounts and fields the original rental branch produced, and fund it through the same
// wallet-hold function the product still uses for legacy orders.
//
// This file is not part of the Convex backend (it lives outside convex/) and is never deployed.
// ═══════════════════════════════════════════════════════════════════════

import type { Id } from "../convex/_generated/dataModel";
import { priceOrder } from "../convex/lib/fees";
import { fundVehicleOrderFromWallet } from "../convex/escrow";

type Runner = { run: <R>(fn: (ctx: any) => Promise<R>) => Promise<R> };
const round2 = (n: number) => Math.round(n * 100) / 100;

export type LegacyRentalArgs = {
  /** The renter's session-less identity: the user id. */
  buyerId: Id<"users">;
  vehicleListingId: Id<"vehicleListings">;
  numberOfDays?: number;
  /** Hold the amount from the buyer's wallet (default) or leave the order PENDING_PAYMENT. */
  payFromWallet?: boolean;
  paymentRail?: "WALLET" | "MOBILE_MONEY" | "BANK_TRANSFER";
  paymentProvider?: string;
  paymentPhone?: string;
  bankEscrowReference?: string;
};

export async function seedLegacyRentalOrder(t: Runner, a: LegacyRentalArgs) {
  return t.run(async (ctx) => {
    const vehicle = await ctx.db.get(a.vehicleListingId);
    if (!vehicle) throw new Error("fixture: vehicle not found");
    const now = Date.now();
    const days = Math.floor(a.numberOfDays ?? 1);
    const baseRental = round2(vehicle.price * days);
    const deposit = Math.max(500, Math.round(baseRental * 0.33));
    const fees = await priceOrder(ctx, "vehicle_rental", baseRental, { hasAgent: false, now });
    const gross = round2(fees.buyerTotal + deposit);
    const payFromWallet = a.payFromWallet ?? (a.paymentRail === undefined || a.paymentRail === "WALLET");
    const rail = a.paymentRail ?? (payFromWallet ? "WALLET" : "MOBILE_MONEY");
    const bank = rail === "BANK_TRANSFER";
    const split60 = round2(fees.payeeNet * 0.6);
    const orderCode = `VK-ESC-${String(now).slice(-6)}-${Math.floor(1000 + Math.random() * 9000)}`;
    const bankRef = bank ? (a.bankEscrowReference ?? `VKTLX-DEAL-${Math.floor(1000 + Math.random() * 9000)}`) : undefined;
    const id: Id<"escrow_orders"> = await ctx.db.insert("escrow_orders", {
      orderCode,
      orderType: "VEHICLE_RENTAL",
      renterOrBuyerId: a.buyerId,
      ownerOrSellerId: vehicle.ownerId,
      vehicleListingId: vehicle._id,
      currency: "SLE",
      baseRentalAmount: baseRental,
      refundableDepositAmount: deposit,
      earnestFeeAmount: 0,
      fullPurchaseAmount: 0,
      grossEscrowAmount: gross,
      platformFeeAmount: fees.platformTotal,
      netMerchantExpected: fees.payeeNet,
      split60ReleasedAmount: 0,
      split40ReleasedAmount: 0,
      depositRefundedAmount: 0,
      depositDamageDeductedAmount: 0,
      status: "PENDING_PAYMENT",
      numberOfDays: days,
      paymentProvider: a.paymentProvider ?? (payFromWallet ? "WALLET" : bank ? "BANK_TRANSFER" : "MONIME"),
      paymentPhone: a.paymentPhone,
      paymentRail: rail,
      bankEscrowReference: bankRef,
      bankClearingStatus: bank ? "PENDING_TRANSFER" : undefined,
      feeSnapshot: fees,
      createdAt: now,
      updatedAt: now,
    });
    let status = "PENDING_PAYMENT";
    if (payFromWallet) {
      // Throws INSUFFICIENT_FUNDS (and rolls the seed back) when the wallet cannot cover it.
      await fundVehicleOrderFromWallet(ctx, id);
      status = "HELD_IN_ESCROW";
    }
    return {
      escrowOrderId: id as string,
      orderCode,
      status,
      grossEscrowAmount: gross,
      platformFeeAmount: fees.platformTotal,
      netMerchantExpected: fees.payeeNet,
      split60Amount: split60,
      split40Amount: round2(fees.payeeNet - split60),
      refundableDeposit: deposit,
      bankEscrowReference: bankRef,
      paymentRail: rail,
    };
  });
}
