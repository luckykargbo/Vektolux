// convex/lib/fees.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Fee & Commission Engine (pure calculation + rule resolution).
//
// Every order computes its fees HERE, from the fee rule in force for its vertical, and stores an
// immutable snapshot of the rule and the resulting breakdown on the order. Later rule changes never
// touch existing orders: their payouts follow their own snapshot.
//
// DEFAULTS reproduce the economics that were hard-coded before this engine existed, exactly
// (same percentages, same fee base, same rounding). With no admin-configured rule, every flow
// produces the same numbers as before. Admins change fees by adding a NEW rule version
// (convex/feeRules.ts); rule rows are never edited in place.
//
// Breakdown (all amounts in the order currency):
//   base             the price of the thing sold/rented (rent, stay, sale price, tour fee …)
//   buyerFee         added ON TOP for the buyer (0 unless a rule enables it)
//   agentGross       agent commission, only when a valid agent relationship exists AND the rule
//                    sets one; paid by the buyer (on top) or by the owner (deducted)
//   platformAgentShare  the platform's share of the agent commission
//   ownerFee         platform fee deducted from the payee (owner / host / seller; for a viewing pass
//                    the payee is the touring agent)
//   buyerTotal       what the buyer pays for the deal (excluding refundable deposits)
//   payeeNet         what the owner / payee receives
//   platformTotal    everything the platform keeps
//   invariant: buyerTotal = payeeNet + agentNet + platformTotal
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";

export const FEE_VERTICALS = [
  "vehicle_rental",
  "vehicle_sale",
  "re_short_stay",
  "re_lease",
  "re_land_purchase",
  "re_viewing_pass",
  "hotel_booking",
  "marketplace_booking",
] as const;
export type FeeVertical = (typeof FEE_VERTICALS)[number];
export const feeVerticalValidator = v.union(...FEE_VERTICALS.map((x) => v.literal(x))) as any;

export type AgentPayer = "buyer" | "owner";

/** Admin-editable part of a rule. */
export type FeeRuleTerms = {
  ownerFeeBps: number;
  buyerFeeBps: number;
  agentCommissionBps: number;
  agentCommissionPayer: AgentPayer;
  platformShareOfAgentCommissionBps: number;
};

/** Fixed per vertical (how the existing flow computes); not admin-editable. */
type VerticalShape = {
  rounding: "cent" | "whole";
  /** "base": owner fee on the base price. "buyer_total": on base + buyer fee (marketplace bookings). */
  ownerFeeBase: "base" | "buyer_total";
  /** Whether the flow can pay an agent commission today. */
  agentCapable: boolean;
  label: string;
};

export const VERTICAL_SHAPES: Record<FeeVertical, VerticalShape> = {
  vehicle_rental: { rounding: "cent", ownerFeeBase: "base", agentCapable: false, label: "Vehicle rental" },
  vehicle_sale: { rounding: "cent", ownerFeeBase: "base", agentCapable: false, label: "Vehicle sale" },
  re_short_stay: { rounding: "cent", ownerFeeBase: "base", agentCapable: false, label: "Property short stay" },
  re_lease: { rounding: "cent", ownerFeeBase: "base", agentCapable: true, label: "Property long-term lease" },
  re_land_purchase: { rounding: "cent", ownerFeeBase: "base", agentCapable: false, label: "Land / house purchase" },
  re_viewing_pass: { rounding: "cent", ownerFeeBase: "base", agentCapable: false, label: "Property viewing pass" },
  hotel_booking: { rounding: "whole", ownerFeeBase: "base", agentCapable: false, label: "Hotel / guest house booking" },
  marketplace_booking: { rounding: "whole", ownerFeeBase: "buyer_total", agentCapable: false, label: "Marketplace booking (hourly stay / vehicle day hire)" },
};

/** Today's economics, unchanged. */
export const DEFAULT_FEE_TERMS: Record<FeeVertical, FeeRuleTerms> = {
  vehicle_rental: terms(1500),
  vehicle_sale: terms(500),
  re_short_stay: terms(1000),
  // tenant pays a 10% agency commission on top; the platform keeps 15% of it
  re_lease: { ownerFeeBps: 0, buyerFeeBps: 0, agentCommissionBps: 1000, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 1500 },
  re_land_purchase: terms(500),
  re_viewing_pass: terms(1500),
  hotel_booking: terms(1000),
  // 5% service fee added for the buyer, then 15% platform commission on the buyer's total
  marketplace_booking: { ownerFeeBps: 1500, buyerFeeBps: 500, agentCommissionBps: 0, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 0 },
};

function terms(ownerFeeBps: number): FeeRuleTerms {
  return { ownerFeeBps, buyerFeeBps: 0, agentCommissionBps: 0, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 0 };
}

const round2 = (n: number) => Math.round(n * 100) / 100;

export type FeeBreakdown = {
  baseAmount: number;
  buyerFee: number;
  ownerFee: number;
  agentCommissionGross: number;
  agentCommissionNet: number;
  platformAgentShare: number;
  platformTotal: number;
  buyerTotal: number;
  payeeNet: number;
};

/** Pure fee calculation. `hasAgent`: a valid agent relationship exists for this deal. */
export function computeFees(vertical: FeeVertical, t: FeeRuleTerms, baseAmount: number, opts: { hasAgent: boolean }): FeeBreakdown {
  const shape = VERTICAL_SHAPES[vertical];
  // Fees are rounded the way each flow always rounded them (cents, or whole leones). Sums follow the
  // old arithmetic too: cent flows round2 their totals; whole flows used plain arithmetic.
  const feeRound = shape.rounding === "whole" ? Math.round : round2;
  const r = shape.rounding === "whole" ? (x: number) => x : round2;
  // rate = bps / 10000 gives exactly the same double as the old literals (0.15, 0.1, 0.05 …)
  const pct = (amount: number, bps: number) => (bps === 0 ? 0 : feeRound(amount * (bps / 10000)));

  const base = baseAmount; // the caller's price, exactly as each flow computed it
  const buyerFee = pct(base, t.buyerFeeBps);
  const agentApplies = shape.agentCapable && opts.hasAgent && t.agentCommissionBps > 0;
  const agentGross = agentApplies ? pct(base, t.agentCommissionBps) : 0;
  const platformAgentShare = agentApplies ? pct(agentGross, t.platformShareOfAgentCommissionBps) : 0;
  const agentNet = r(agentGross - platformAgentShare);
  const agentOnTop = agentApplies && t.agentCommissionPayer === "buyer" ? agentGross : 0;
  const agentDeducted = agentApplies && t.agentCommissionPayer === "owner" ? agentGross : 0;

  const buyerTotal = r(base + buyerFee + agentOnTop);
  let ownerFee: number;
  let payeeNet: number;
  let platformTotal: number;
  if (shape.ownerFeeBase === "buyer_total") {
    // marketplace bookings: commission on the buyer's total; the payee receives the rest of it
    ownerFee = pct(r(base + buyerFee), t.ownerFeeBps);
    payeeNet = r(buyerTotal - ownerFee);
    platformTotal = ownerFee;
  } else {
    ownerFee = pct(base, t.ownerFeeBps);
    payeeNet = r(base - ownerFee - agentDeducted);
    platformTotal = r(ownerFee + buyerFee + platformAgentShare);
  }
  return {
    baseAmount: base,
    buyerFee,
    ownerFee,
    agentCommissionGross: agentGross,
    agentCommissionNet: agentNet,
    platformAgentShare,
    platformTotal,
    buyerTotal,
    payeeNet,
  };
}

// ─── snapshot stored on every order ──────────────────────────────────

export const feeSnapshotValidator = v.object({
  vertical: v.string(),
  ruleSource: v.union(v.literal("default"), v.literal("configured")),
  ruleId: v.optional(v.string()),
  ruleVersion: v.number(),
  ownerFeeBps: v.number(),
  buyerFeeBps: v.number(),
  agentCommissionBps: v.number(),
  agentCommissionPayer: v.union(v.literal("buyer"), v.literal("owner")),
  platformShareOfAgentCommissionBps: v.number(),
  rounding: v.union(v.literal("cent"), v.literal("whole")),
  ownerFeeBase: v.union(v.literal("base"), v.literal("buyer_total")),
  agentApplied: v.boolean(),
  baseAmount: v.number(),
  buyerFee: v.number(),
  ownerFee: v.number(),
  agentCommissionGross: v.number(),
  agentCommissionNet: v.number(),
  platformAgentShare: v.number(),
  platformTotal: v.number(),
  buyerTotal: v.number(),
  payeeNet: v.number(),
  computedAt: v.number(),
});

export type FeeSnapshot = FeeBreakdown & {
  vertical: string;
  ruleSource: "default" | "configured";
  ruleId?: string;
  ruleVersion: number;
  ownerFeeBps: number;
  buyerFeeBps: number;
  agentCommissionBps: number;
  agentCommissionPayer: AgentPayer;
  platformShareOfAgentCommissionBps: number;
  rounding: "cent" | "whole";
  ownerFeeBase: "base" | "buyer_total";
  agentApplied: boolean;
  computedAt: number;
};

export type ResolvedRule = { terms: FeeRuleTerms; source: "default" | "configured"; ruleId?: string; version: number };

/** The rule in force for a vertical at `now`: the newest active configured rule, else the default. */
export async function resolveFeeRule(ctx: { db: any }, vertical: FeeVertical, now: number = Date.now()): Promise<ResolvedRule> {
  const rows = await ctx.db
    .query("fee_rules")
    .withIndex("by_vertical_effectiveFrom", (q: any) => q.eq("vertical", vertical).lte("effectiveFrom", now))
    .order("desc")
    .take(50);
  const row = rows.find((x: any) => x.status === "active");
  if (!row) return { terms: DEFAULT_FEE_TERMS[vertical], source: "default", version: 0 };
  return {
    terms: {
      ownerFeeBps: row.ownerFeeBps,
      buyerFeeBps: row.buyerFeeBps,
      agentCommissionBps: row.agentCommissionBps,
      agentCommissionPayer: row.agentCommissionPayer,
      platformShareOfAgentCommissionBps: row.platformShareOfAgentCommissionBps,
    },
    source: "configured",
    ruleId: row._id as string,
    version: row.version,
  };
}

/** Resolve the rule, compute the breakdown, and return the immutable snapshot to store on the order. */
export async function priceOrder(
  ctx: { db: any },
  vertical: FeeVertical,
  baseAmount: number,
  opts: { hasAgent: boolean; now?: number }
): Promise<FeeSnapshot> {
  const now = opts.now ?? Date.now();
  const rule = await resolveFeeRule(ctx, vertical, now);
  const shape = VERTICAL_SHAPES[vertical];
  const b = computeFees(vertical, rule.terms, baseAmount, { hasAgent: opts.hasAgent });
  return {
    vertical,
    ruleSource: rule.source,
    ...(rule.ruleId ? { ruleId: rule.ruleId } : {}),
    ruleVersion: rule.version,
    ...rule.terms,
    rounding: shape.rounding,
    ownerFeeBase: shape.ownerFeeBase,
    agentApplied: b.agentCommissionGross > 0,
    ...b,
    computedAt: now,
  };
}
