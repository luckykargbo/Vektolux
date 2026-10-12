# Unpaid escrow orders: lifecycle gap and expiry plan — INVESTIGATION ONLY
Nothing was implemented, cancelled, expired or changed. All jobs remain disabled.

## 1. Files and functions
| Concern | Where |
|---|---|
| Vehicle order create / fund | `convex/escrow.ts`: `initiateEscrowOrder`, `fundVehicleOrderFromWallet`, `fundVehicleOrderFromExternal` |
| Real-estate contract create / fund | `convex/realEstateEscrow.ts`: `initiateRealEstateEscrow`, `fundReContractFromWallet`, `fundReContractFromExternal` |
| Inspection pass create / fund | `realEstateEscrow.ts`: `initiateInspectionPass`, `fundInspectionPassFromWallet` |
| Monime-bound payment | `payments.ts`: `initiateMoniMePayment` → `recordPendingMoniMeTransaction` → `settleMoniMeReference` → `processMoniMeWebhookSuccess` → `fundEscrowFromDeposit` |
| Bank wire | `payments.ts`: `generateBankEscrowReference`, `confirmBankEscrowTransfer` (admin) |
| Manual claim | `payments.ts`: `submitManualPaymentClaim`, `approveClaimCore` (admin) |
| Holds / ledger | `walletCore.ts`: `holdFunds`, `fundEscrowFromExternalPayment` |
| Deletion obligation check | `accountDeletion.ts`: `openObligation` |
| UI | `lib/features/mobility/.../my_escrow_orders_screen.dart`, `escrow_tracking_screen.dart` |

## 2. State table (as coded)
| Object | Created in | Funded by | Terminal states that exist in code |
|---|---|---|---|
| `escrow_orders` | `PENDING_PAYMENT`, or `HELD_IN_ESCROW` immediately when paid from the wallet | wallet hold / Monime-verified deposit + soft hold / admin bank confirmation / approved claim | `SETTLED`, `REFUNDED`; **`CANCELLED` exists in the schema but nothing ever sets it** |
| `re_escrow_contracts` | `CREATED` (or `FUNDS_LOCKED` for wallet rail) | same four paths | `FULLY_SETTLED`, `REFUNDED`; **`CANCELLED` never set** |
| `re_inspection_passes` | `CREATED` (fee held → `FUNDS_LOCKED`) | wallet hold / Monime / claim | `CANCELLED` never set; `otpExpiresAt = scheduled + 4 h` makes an unpaid pass unusable after that |
| `bookings` (related) | `pending_payment` | wallet / Monime / claim | `cancelled` via `cancelBooking` (buyer or vendor) — exists |

`PENDING_PAYMENT`/`CREATED` is left only by funding. Money is never held while an order is unpaid.
There is **no cancel path and no expiry** for vehicle orders, real-estate contracts or passes.

## 3. What an order can be bound to (all readable from server state)
| Binding | Where recorded | Lookup |
|---|---|---|
| Monime checkout / payment code | `transactions` top_up, `referenceType="escrow_checkout"`, `referenceId="vehicle:<id>"` / `re:<id>` / `pass:<id>` / `booking:<id>`; `gatewayReference` = Monime object id; status pending/completed/failed | `by_reference` index ✓ |
| Held / reserved funds | `transactions` escrow_lock, `referenceType="vehicle_escrow"` / `re_escrow` / `re_inspection_pass`, `referenceId=<id>`; idempotency key `vesc:<id>:fund`, `rec:<id>:fund`, `rip:<id>:fund` | `by_reference` ✓ |
| Direct external payment | `transactions` escrow_lock with `gatewayProvider/gatewayReference` (bank wire) | `by_reference` ✓ |
| Bank wire in flight | order field `bankEscrowReference` + `bankClearingStatus: PENDING_TRANSFER` (the reference is **auto-generated at creation**, the customer may wire any time, **no record exists until an admin confirms**) | `by_bank_ref` ✓ — but non-payment is **unprovable** |
| Manual claim | `escrow_payment_claims.escrowOrderId` / `reContractId` / `bookingId`, status `PENDING_PAYMENT`/`PENDING_APPROVAL`/`ESCROW_LOCKED` | **no index** on those fields (only by user / status) |
| Dispute / refund | `escrow_disputes`, `re_escrow_disputes`, `payment_reversals` | by order/contract ✓ |
| Caution deposit / milestones (RE) | **created at contract creation, before any money**: `re_caution_deposits` status `LOCKED` with `heldAmount = deposit`, and `re_escrow_milestones` `CREATED` | by contract ✓ |
| Listing reservation | none: orders do not reserve a vehicle or property | — |

## 4. How account deletion sees an order today
`openObligation`: escrow orders (buyer or seller) with status not in {SETTLED, REFUNDED, CANCELLED} ⇒ `ESCROW_OPEN`;
RE contracts not in {FULLY_SETTLED, REFUNDED, CANCELLED} ⇒ `RE_ESCROW_OPEN`; then, for terminal contracts, any
caution deposit `LOCKED|REFUND_INITIATED|IN_DISPUTE` ⇒ `CAUTION_DEPOSIT_OPEN`; passes similarly.
Consequences: **an abandoned unpaid order blocks erasure forever**, and an expired contract would *still*
block via its `LOCKED` caution row unless that row is closed/ignored as part of expiry.

## 5. What can be proven safely from existing records
Provable: status is still `PENDING_PAYMENT`/`CREATED`; age (`createdAt`); no hold/escrow_lock exists; no
Monime top_up references it (and any referenced one is `failed`); no claim links to it; no dispute; no
reversal; payment rail; paid-from-wallet orders never sit in this state.
**Not provable:** that nobody wired money for a `BANK_TRANSFER` order (no record until admin confirms), and
that a Monime checkout with no/unfinished record is dead (Monime default checkout lifetime is not set by us
and not documented in the repo).

## 6. Existing constants and rules (none is an order expiry)
`otpExpiresAt` = scheduled + 4 h (passes); `BOOKING_RELEASE_DELAY_MS` 24 h; Monime reconcile window 48 h;
OTP 5 min; deletion window 30 days; password-reset/email codes 10–15 min. **There is no expiry duration for
unpaid orders; I am not inventing one.**

## 7. Recommended policy (for approval)
An order/contract/pass is *eligible* only if ALL hold, evaluated inside ONE mutation:
1. status is `PENDING_PAYMENT` / `CREATED` and `createdAt` older than **N days**;
2. `paymentRail` is **not** `BANK_TRANSFER` (bank-wire orders: admin-only closure in v1, plus a reminder);
3. no `transactions` row with referenceType `escrow_checkout` + this tag whose status is `pending` or
   `completed`, and none `escrow_lock` for it (only `failed` Monime rows allowed — i.e. Monime already
   reported expired/cancelled);
4. no claim in `PENDING_PAYMENT|PENDING_APPROVAL|ESCROW_LOCKED|APPROVED` for it;
5. no dispute/reversal; `escrowHeldRemaining` unset/0; `bankClearingStatus` not `CLEARED`.
**Recommended N: 14 days** for mobile-money/wallet-rail vehicle and real-estate orders (long enough for a
cooling-off and a slow Monime/claim review; deposits themselves are never expired by age), and
**pass: scheduled time + 4 h** (already the pass's own deadline). Business decision needed: confirm N,
whether bank-wire orders ever auto-expire (recommended: no), and the customer notice wording.
Transition: set `CANCELLED` + `cancelledAt` + `cancelReason: "unpaid_expired"` + `cancelledBy: "system"`;
for RE also set the caution row to a closed state with `heldAmount: 0` and milestones `CANCELLED`;
notify buyer and seller; never touch wallets or the ledger.

## 8. Late-payment safety (the part that must not be lost)
- **Monime late completion** after expiry: already safe — `processMoniMeWebhookSuccess` credits the
  *wallet* first, then `fundEscrowFromDeposit` returns "not awaiting payment" (soft) ⇒ money is in the
  buyer's wallet and the buyer is notified. Keep this ordering; add a test.
- **Admin bank confirmation** after expiry: **currently throws** "not awaiting payment" (money at the bank,
  nothing credited). Must change to credit the buyer's wallet with the verified wire (idempotent on the
  provider reference) instead of failing. Required before any bank-rail order may expire at all.
- **Claim approval** after expiry: already credits the wallet first (soft funding). Safe.
- **Race:** Convex mutations are serializable; expiry re-reads status and bindings in the same transaction
  as the write, so a concurrent funding either commits first (expiry then sees `HELD_IN_ESCROW` and skips)
  or retries and sees `CANCELLED` (funding returns "not awaiting payment"; money path above applies).

## 9. Missing state / indexes
- `escrow_orders`: index `["status","createdAt"]`; fields `cancelledAt`, `cancelReason`, `cancelledBy`.
- `re_escrow_contracts`: index `["currentState","createdAt"]` (+ same fields).
- `escrow_payment_claims`: indexes on `escrowOrderId` and `reContractId` (or scan the buyer's pending claims).
- `re_caution_deposits`: either a closed status (e.g. `VOID`) or make the deletion check ignore deposits of
  `CANCELLED` contracts.
- `accountDeletion.openObligation`: ensure `CANCELLED` contracts/orders are terminal AND their deposit rows
  do not block.
- **Client:** `my_escrow_orders_screen.dart` treats `CANCELLED_REFUNDED` (a status the server never sends)
  as closed; `CANCELLED` would appear under "Active". Map `CANCELLED` (and `REFUNDED`) before any expiry ships.

## 10. Minimal implementation plan (after approval)
1. Schema: optional cancel fields, indexes, caution status; regenerate types.
2. `internal.escrowExpiry.expireUnpaidOrders({ now?, limit })`: bounded batch; per order one transaction with
   the §7 checks; idempotent (already `CANCELLED` ⇒ skip); writes the fields + notifications; returns counts.
3. Fix `confirmBankEscrowTransfer` (and the external-funding helpers) to credit the wallet when the target
   is no longer awaiting payment.
4. Update the deletion check for cancelled contracts' deposits; Flutter status mapping and labels.
5. Cron entry behind its own switch, **off**; admin-visible dry-run query (counts + ids, no writes).

## 11. Regression-test plan (to write with the implementation)
Eligible stale order expires once (second run no-op, no new rows); fresh order untouched; bound pending or
completed Monime row blocks expiry; failed Monime row allows it; pending/approved claim blocks; held funds /
`HELD_IN_ESCROW` never touched; bank-rail order never auto-expires; pass expires only after its own deadline;
late Monime completion after expiry lands in the wallet exactly once; admin bank confirmation after expiry
credits the wallet; concurrent expiry vs funding stays consistent (one wins, no double ledger entry);
repeated attempts create no ledger operations; account deletion unblocks for an expired order/contract and
stays blocked for a funded one; other order types (bookings, hotel) and other roles unaffected.

---

## Implementation notes (as built)

**Status: implemented, NOT enabled.** Nothing was deployed, committed, or run against real records.

### Policy as implemented
| Record | Expires when | Never expires when |
|---|---|---|
| Vehicle order (`escrow_orders`, `PENDING_PAYMENT`) | `paymentRail` is `MOBILE_MONEY` or `WALLET` and `createdAt` is ≥ 14 days old | rail is `BANK_TRANSFER` (or missing/legacy), any blocker below |
| RE contract (`re_escrow_contracts`, `CREATED`) | same | same |
| Inspection pass (`re_inspection_passes`, `CREATED`) | `otpExpiresAt` (scheduled time + 4 h) has passed | any blocker below, pass already used |

Blockers (record is skipped and counted under its code): `NOT_AWAITING_PAYMENT`, `TOO_RECENT`, `BEFORE_DEADLINE`, `BANK_TRANSFER_RAIL`, `RAIL_NOT_ELIGIBLE`, `FUNDS_ALREADY_MOVED`, `FUNDS_HELD_OR_MOVED`, `PROVIDER_PAYMENT_UNRESOLVED` (any `escrow_checkout` transaction not `failed`), `CLAIM_PRESENT` (any claim not `REJECTED`), `DISPUTE`, `LEDGER_ACTIVITY`, `REVERSAL`, `CAUTION_DEPOSIT_ACTIVE`, `MILESTONE_ACTIVE`, `PASS_USED`.

### Effects
- Status becomes `CANCELLED` with `cancelledAt`, `cancelReason: "unpaid_expired"`, `cancelledBy: "system_expiry"`.
- RE contracts: unfunded caution deposit rows become `VOID` (`heldAmount: 0`, history preserved) and milestones `CANCELLED`, so the contract no longer blocks account deletion.
- Wallets, `transactions` and ledger rows are never created, altered or removed by expiry.
- Notifications go once to buyer and seller/beneficiary/agent; they tell the buyer to contact support with a payment reference if they already paid, and do not claim a refund.

### Safety
- Eligibility is re-evaluated inside the same mutation that writes (Convex mutations are serializable), so a funding racing expiry yields exactly one outcome.
- Re-runs are idempotent; batches are bounded (`limit` default 25, max 100).
- Job switch `ESCROW_ORDER_EXPIRY_JOBS_ENABLED` in `convex/crons.ts` is **false**. `escrowExpiry.adminExpiryDryRun` (admin only) lists eligible/blocked records with no writes.
- Late Monime confirmation / approved claims: wallet is credited first (idempotent on provider reference); a cancelled order is not funded, so money lands in the wallet, not lost.
- Late bank wire for a `CANCELLED` target: `confirmBankEscrowTransfer` credits the buyer's wallet once (idempotent on the bank transaction id) and writes an audit log. Bank-rail orders are never auto-cancelled in this phase, so this path is only reachable if an admin cancels one.

### Known remaining risks
- Legacy orders with no `paymentRail` never expire.
- Blocked candidates can occupy the bounded window; repeat runs make progress only past them if the oldest ones become eligible.
- Bank-transfer orders pile up until an admin acts (listed by the dry run).
- Monime's own checkout lifetime is unverified; a customer paying after 14 days is handled by the wallet-credit path above, not auto-funding.
- The seven-day agent verification requirement is out of scope and still outstanding (see `docs/agent-onboarding-audit.md`).
