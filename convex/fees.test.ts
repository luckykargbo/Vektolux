/// <reference types="vite/client" />
// Fee engine: with the DEFAULT rules it must reproduce, to the cent, the formulas that were
// hard-coded in each flow before the engine existed. The legacy formulas are copied verbatim below.

import { describe, expect, test } from "vitest";
import { computeFees, DEFAULT_FEE_TERMS, FEE_VERTICALS, FeeRuleTerms, FeeVertical } from "./lib/fees";

const round2 = (n: number) => Math.round(n * 100) / 100;

// ── legacy formulas (as they were in escrow.ts, realEstateEscrow.ts, hotelBookings.ts, bookings.ts) ──
const legacy = {
  vehicle_rental: (base: number) => {
    const platformFee = round2(base * 0.15);
    return { platformTotal: platformFee, payeeNet: round2(base - platformFee), buyerTotal: base };
  },
  vehicle_sale: (full: number) => {
    const platformFee = round2(full * 0.05);
    return { platformTotal: platformFee, payeeNet: round2(full - platformFee), buyerTotal: full };
  },
  re_short_stay: (base: number) => {
    const platformFee = round2(base * 0.1);
    return { platformTotal: platformFee, payeeNet: round2(base - platformFee), buyerTotal: base };
  },
  re_lease: (base: number) => {
    const rawCommission = round2(base * 0.1);
    const platformFee = round2(rawCommission * 0.15);
    const agentCommission = round2(rawCommission - platformFee);
    return { platformTotal: platformFee, payeeNet: base, buyerTotal: round2(base + rawCommission), agentNet: agentCommission };
  },
  re_land_purchase: (base: number) => {
    const platformFee = round2(base * 0.05);
    return { platformTotal: platformFee, payeeNet: round2(base - platformFee), buyerTotal: base };
  },
  re_viewing_pass: (fee: number) => {
    const platformFee = round2(fee * 0.15);
    return { platformTotal: platformFee, payeeNet: round2(fee - platformFee), buyerTotal: fee };
  },
  hotel_booking: (subtotal: number) => {
    const commissionAmount = Math.round(subtotal * 0.1);
    return { platformTotal: commissionAmount, payeeNet: subtotal - commissionAmount, buyerTotal: subtotal };
  },
  marketplace_booking: (subtotal: number) => {
    const serviceFee = Math.round(subtotal * 0.05);
    const totalAmount = subtotal + serviceFee;
    const platformCommission = Math.round(totalAmount * 0.15);
    return { platformTotal: platformCommission, payeeNet: totalAmount - platformCommission, buyerTotal: totalAmount, buyerFee: serviceFee };
  },
} as const;

/** Deterministic pseudo-random amounts: whole, cents, .5 / .005 edges, tiny and huge. */
function amounts(vertical: FeeVertical): number[] {
  const out = [0.01, 0.05, 0.1, 1, 1.5, 9.99, 10, 33.33, 99.995, 100, 150.5, 333.335, 999.99, 1000, 12345.67, 1_000_000, 2_500_000.5, 99_999_999.99];
  let s = 12345;
  for (let i = 0; i < 4000; i++) {
    s = (s * 1103515245 + 12345) % 2147483648;
    const r = s / 2147483648;
    const scale = [10, 1_000, 100_000, 10_000_000][i % 4];
    out.push(Math.round(r * scale * 100) / 100);
  }
  // Feed each flow the base it really computes: marketplace subtotals are whole numbers; the cent
  // flows round their base to cents (round2(price × days) etc.) before fees; hotel subtotals are
  // NOT rounded (pricePerNight × nights), so they keep the raw 3-decimal edge values.
  if (vertical === "marketplace_booking") return out.map(Math.round).filter((x) => x > 0);
  if (vertical === "hotel_booking") return out;
  return out.map(round2).filter((x) => x > 0);
}

describe("defaults reproduce the pre-engine economics exactly", () => {
  for (const vertical of FEE_VERTICALS) {
    test(vertical, () => {
      const hasAgent = vertical === "re_lease"; // lease always paid its commission to the listing party
      for (const base of amounts(vertical)) {
        const got = computeFees(vertical, DEFAULT_FEE_TERMS[vertical], base, { hasAgent });
        const want: any = (legacy as any)[vertical](base);
        expect(got.platformTotal, `${vertical} platform @${base}`).toBe(want.platformTotal);
        expect(got.payeeNet, `${vertical} payee @${base}`).toBe(want.payeeNet);
        expect(got.buyerTotal, `${vertical} buyer @${base}`).toBe(want.buyerTotal);
        if (want.agentNet !== undefined) expect(got.agentCommissionNet).toBe(want.agentNet);
        if (want.buyerFee !== undefined) expect(got.buyerFee).toBe(want.buyerFee);
      }
    });
  }

  test("no buyer fee is active on any existing flow except the pre-existing marketplace service fee", () => {
    for (const vertical of FEE_VERTICALS) {
      const expected = vertical === "marketplace_booking" ? 500 : 0;
      expect(DEFAULT_FEE_TERMS[vertical].buyerFeeBps, vertical).toBe(expected);
    }
  });
});

describe("engine invariants for any rule", () => {
  const rules: FeeRuleTerms[] = [
    { ownerFeeBps: 500, buyerFeeBps: 500, agentCommissionBps: 0, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 0 },
    { ownerFeeBps: 800, buyerFeeBps: 250, agentCommissionBps: 300, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 2000 },
    { ownerFeeBps: 0, buyerFeeBps: 0, agentCommissionBps: 1000, agentCommissionPayer: "owner", platformShareOfAgentCommissionBps: 1500 },
    { ownerFeeBps: 5000, buyerFeeBps: 5000, agentCommissionBps: 5000, agentCommissionPayer: "owner", platformShareOfAgentCommissionBps: 10000 },
  ];
  test("buyerTotal = payeeNet + agentNet + platformTotal (cent flows exact to the cent)", () => {
    for (const vertical of FEE_VERTICALS) {
      for (const t of rules) {
        for (const base of amounts(vertical).slice(0, 600)) {
          for (const hasAgent of [true, false]) {
            const b = computeFees(vertical, t, base, { hasAgent });
            expect(round2(b.payeeNet + b.agentCommissionNet + b.platformTotal)).toBe(round2(b.buyerTotal));
            expect(b.buyerFee).toBeGreaterThanOrEqual(0);
            expect(b.ownerFee).toBeGreaterThanOrEqual(0);
          }
        }
      }
    }
    }, 60_000); // CPU-heavy sweep: allow time when the whole suite runs in parallel

  test("the user's 1,000,000 example: 5% buyer fee + 5% owner commission (no doubling)", () => {
    const b = computeFees("re_land_purchase", { ownerFeeBps: 500, buyerFeeBps: 500, agentCommissionBps: 0, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 0 }, 1_000_000, { hasAgent: false });
    expect(b.buyerFee).toBe(50_000);
    expect(b.buyerTotal).toBe(1_050_000);
    expect(b.ownerFee).toBe(50_000);
    expect(b.payeeNet).toBe(950_000);
    expect(b.platformTotal).toBe(100_000);
  });

  test("agent commission applies only where the flow supports agents AND a valid agent relationship exists", () => {
    const t: FeeRuleTerms = { ownerFeeBps: 0, buyerFeeBps: 0, agentCommissionBps: 1000, agentCommissionPayer: "buyer", platformShareOfAgentCommissionBps: 0 };
    expect(computeFees("re_lease", t, 1000, { hasAgent: false }).agentCommissionGross).toBe(0);
    expect(computeFees("re_lease", t, 1000, { hasAgent: true }).agentCommissionGross).toBe(100);
    expect(computeFees("vehicle_sale", t, 1000, { hasAgent: true }).agentCommissionGross).toBe(0); // not agent-capable
  });
});
