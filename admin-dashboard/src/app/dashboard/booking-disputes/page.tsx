"use client";
// src/app/dashboard/booking-disputes/page.tsx — Marketplace booking disputes & escrow settlement.
// Every amount shown and moved is decided by the Convex backend; this page only displays it and
// sends the admin's decision + note (plus the server amount the admin confirmed, as a staleness check).
import { Fragment, useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type View = "open" | "held" | "resolved";
type Resolution = "release_to_vendor" | "refund_buyer";
interface Person {
  name: string;
  email: string | null;
}
interface Row {
  id: string;
  listingTitle: string;
  listingType: string;
  bookingType: string;
  buyer: Person | null;
  vendor: Person | null;
  startTime: number;
  endTime: number;
  subtotal: number;
  serviceFee: number;
  totalAmount: number;
  currency: string;
  status: string;
  paymentStatus: string;
  settlementStatus: string | null;
  disputedBy: "buyer" | "vendor" | null;
  disputeReason: string | null;
  disputedAt: number | null;
  autoReleaseAt: number | null;
  releasedAt: number | null;
  releasedBy: string | null;
  refundedAt: number | null;
  refundReason: string | null;
  escrow: {
    escrowTransactionCode: string | null;
    escrowStatus: string | null;
    amountPaid: number;
    platformFee: number;
    vendorAmount: number;
    heldAmount: number;
    refundableAmount: number;
    currency: string;
  } | null;
  transactions: { transactionCode: string | null; type: string; amount: number; netAmount: number | null; status: string; escrowStatus: string | null; createdAt: number | null; party: string }[];
  events: { action: string; actorRole: string; actorName: string | null; amount: number | null; platformFee: number | null; transactionCode: string | null; ledgerCode: string | null; note: string | null; at: number }[];
  audit: { action: string; adminName: string | null; resolution: string | null; amount: number | null; note: string | null; at: number }[];
}

const when = (ms: number | null | undefined) => (ms ? new Date(ms).toLocaleString() : "—");
const money = (n: number | null | undefined) =>
  typeof n === "number" ? n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "—";
const TYPE: Record<string, string> = {
  hourly_guesthouse: "Hourly stay",
  vehicle_rental: "Vehicle day hire",
  property_inspection: "Property inspection",
  vehicle_inspection: "Vehicle inspection",
};
const STATE_BADGE: Record<string, string> = {
  disputed: styles.badgeDisputed,
  held: styles.badgeHeld,
  released: styles.badgeReleased,
  refunded: styles.badgeSettled,
};

export default function BookingDisputesPage() {
  const [view, setView] = useState<View>("open");
  const [rows, setRows] = useState<Row[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch(`/api/booking-disputes?view=${view}`);
      const body = await res.json();
      if (body.success) setRows(body.data);
      else setError(body.error ?? "Could not load booking disputes.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, [view]);

  useEffect(() => {
    load();
  }, [load]);

  async function decide(r: Row, resolution: Resolution) {
    if (!r.escrow || r.escrow.heldAmount <= 0) return;
    const c = r.escrow.currency;
    const amount = resolution === "release_to_vendor" ? r.escrow.vendorAmount : r.escrow.refundableAmount;
    const what =
      resolution === "release_to_vendor"
        ? `RELEASE TO VENDOR\n\n${r.vendor?.name ?? "Vendor"} receives ${c} ${money(r.escrow.vendorAmount)}; Vektolux keeps the ${c} ${money(r.escrow.platformFee)} fee.`
        : `REFUND BUYER\n\n${r.buyer?.name ?? "Buyer"} is refunded ${c} ${money(r.escrow.refundableAmount)} (everything held, including the service fee).`;
    const note = window.prompt(`${what}\n\nBooking ${r.id}\nThe server re-checks this amount before moving any money.\n\nReason / note (required, audited):`);
    if (note === null) return;
    if (note.trim().length < 5) {
      setMsg("A note of at least 5 characters is required.");
      return;
    }
    if (!window.confirm(`Confirm: ${resolution === "release_to_vendor" ? "release" : "refund"} ${c} ${money(amount)}? This cannot be undone here.`)) return;
    setBusy(true);
    setMsg("");
    try {
      const res = await adminFetch("/api/booking-disputes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ bookingId: r.id, resolution, note, expectedAmount: amount }),
      });
      const body = await res.json();
      setMsg(
        body.success
          ? `${resolution === "release_to_vendor" ? "Released" : "Refunded"} ${c} ${money(body.data.amount)}.`
          : body.error ?? "The decision could not be applied."
      );
      load();
    } catch {
      setMsg("Network connection error");
    }
    setBusy(false);
  }

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Booking Disputes</h1>
          <p className={styles.subtitle}>
            Marketplace bookings whose payment is held in escrow. A dispute freezes the money (no automatic release) until an
            administrator releases it to the vendor or refunds the buyer. Amounts come from the server.
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <select value={view} onChange={(e) => setView(e.target.value as View)} style={{ padding: 8, borderRadius: 8 }}>
            <option value="open">Open disputes</option>
            <option value="held">Held (awaiting release)</option>
            <option value="resolved">Resolved disputes</option>
          </select>
          <button className={styles.refreshBtn} onClick={load} disabled={loading}>
            <RefreshCcw size={16} /> Refresh
          </button>
        </div>
      </div>

      {error && <p style={{ color: "#dc2626" }}>{error}</p>}
      {msg && <p style={{ fontSize: 14 }}>{msg}</p>}

      <div className={styles.tableCard}>
        <div style={{ overflowX: "auto" }}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Booking</th>
                <th>Buyer / Vendor</th>
                <th>When</th>
                <th>Paid</th>
                <th>Held / Refundable</th>
                <th>Fee</th>
                <th>Dispute</th>
                <th>Escrow</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !loading && (
                <tr>
                  <td colSpan={9} className={styles.statSub}>
                    {view === "open" ? "No open disputes." : view === "held" ? "No bookings awaiting release." : "No resolved disputes."}
                  </td>
                </tr>
              )}
              {rows.map((r) => {
                const actionable = !!r.escrow && r.escrow.heldAmount > 0 && (r.settlementStatus === "disputed" || r.settlementStatus === "held");
                return (
                  <Fragment key={r.id}>
                    <tr>
                      <td style={{ fontSize: 13 }}>
                        <div style={{ fontFamily: "monospace", fontSize: 12 }}>{r.id}</div>
                        {r.listingTitle}
                        <div className={styles.statSub}>{TYPE[r.bookingType] ?? r.bookingType}</div>
                      </td>
                      <td style={{ fontSize: 13 }}>
                        {r.buyer?.name ?? "—"}
                        <div className={styles.statSub}>vendor: {r.vendor?.name ?? "—"}</div>
                      </td>
                      <td style={{ fontSize: 13 }}>
                        {when(r.startTime)}
                        <div className={styles.statSub}>to {when(r.endTime)}</div>
                      </td>
                      <td>
                        {r.currency} {money(r.escrow?.amountPaid ?? r.totalAmount)}
                      </td>
                      <td>
                        {money(r.escrow?.heldAmount)} / {money(r.escrow?.refundableAmount)}
                      </td>
                      <td>{money(r.escrow?.platformFee)}</td>
                      <td style={{ fontSize: 13, maxWidth: 260 }}>
                        {r.disputedAt ? (
                          <>
                            Opened by <strong>{r.disputedBy}</strong> · {when(r.disputedAt)}
                            <div className={styles.statSub}>{r.disputeReason}</div>
                          </>
                        ) : (
                          <span className={styles.statSub}>No dispute</span>
                        )}
                        {r.autoReleaseAt && <div className={styles.statSub}>Auto-release: {when(r.autoReleaseAt)}</div>}
                      </td>
                      <td>
                        <span className={`${styles.badge} ${STATE_BADGE[r.settlementStatus ?? ""] ?? ""}`}>{r.settlementStatus ?? "—"}</span>
                        <div className={styles.statSub} style={{ fontFamily: "monospace" }}>
                          {r.escrow?.escrowTransactionCode ?? "—"}
                        </div>
                      </td>
                      <td style={{ whiteSpace: "nowrap" }}>
                        <button className={styles.actionBtn} onClick={() => setOpen(open === r.id ? null : r.id)}>
                          {open === r.id ? "Hide" : "View booking"}
                        </button>
                        {actionable && (
                          <div style={{ display: "flex", gap: 6, marginTop: 6 }}>
                            <button className={`${styles.actionBtn} ${styles.actionBtnEmerald}`} disabled={busy} onClick={() => decide(r, "release_to_vendor")}>
                              Release to vendor
                            </button>
                            <button className={styles.actionBtn} disabled={busy} onClick={() => decide(r, "refund_buyer")}>
                              Refund buyer
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                    {open === r.id && (
                      <tr>
                        <td colSpan={9} style={{ background: "#f8fafc", fontSize: 13 }}>
                          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: 12 }}>
                            <div>
                              <div className={styles.statLabel}>Booking</div>
                              <div>Status: {r.status} · payment {r.paymentStatus}</div>
                              <div>
                                Subtotal {money(r.subtotal)} + service fee {money(r.serviceFee)} = {r.currency} {money(r.totalAmount)}
                              </div>
                              <div>Buyer: {r.buyer?.name ?? "—"} {r.buyer?.email ? `(${r.buyer.email})` : ""}</div>
                              <div>Vendor: {r.vendor?.name ?? "—"} {r.vendor?.email ? `(${r.vendor.email})` : ""}</div>
                              {r.releasedAt && <div>Released {when(r.releasedAt)} ({r.releasedBy})</div>}
                              {r.refundedAt && <div>Refunded {when(r.refundedAt)}: {r.refundReason}</div>}
                            </div>
                            <div>
                              <div className={styles.statLabel}>Escrow (server)</div>
                              {r.escrow ? (
                                <>
                                  <div>Escrow transaction: {r.escrow.escrowTransactionCode ?? "—"} ({r.escrow.escrowStatus})</div>
                                  <div>Vendor would receive: {money(r.escrow.vendorAmount)}</div>
                                  <div>Platform fee: {money(r.escrow.platformFee)}</div>
                                  <div>Refundable to buyer: {money(r.escrow.refundableAmount)}</div>
                                </>
                              ) : (
                                <div className={styles.statSub}>No escrow lock found.</div>
                              )}
                            </div>
                            <div>
                              <div className={styles.statLabel}>Wallet transactions</div>
                              {r.transactions.map((t, i) => (
                                <div key={i}>
                                  {when(t.createdAt)} · {t.party} · {t.type} {money(t.amount)} · {t.status}
                                  {t.escrowStatus ? ` (${t.escrowStatus})` : ""} · <span style={{ fontFamily: "monospace" }}>{t.transactionCode ?? "—"}</span>
                                </div>
                              ))}
                            </div>
                          </div>
                          <div className={styles.statLabel} style={{ marginTop: 12 }}>
                            Settlement history
                          </div>
                          {r.events.length === 0 && <div className={styles.statSub}>No history recorded for this booking.</div>}
                          {r.events.map((e, i) => (
                            <div key={i} style={{ padding: "2px 0" }}>
                              {when(e.at)} — <strong>{e.action}</strong> by {e.actorName ?? e.actorRole} ({e.actorRole})
                              {e.amount !== null ? ` · ${money(e.amount)}` : ""}
                              {e.platformFee !== null ? ` · fee ${money(e.platformFee)}` : ""}
                              {e.transactionCode ? ` · tx ${e.transactionCode}` : ""}
                              {e.ledgerCode ? ` · ledger ${e.ledgerCode}` : ""}
                              {e.note ? ` — ${e.note}` : ""}
                            </div>
                          ))}
                          {r.audit.length > 0 && (
                            <>
                              <div className={styles.statLabel} style={{ marginTop: 12 }}>
                                Admin audit log
                              </div>
                              {r.audit.map((a, i) => (
                                <div key={i}>
                                  {when(a.at)} — {a.action} by {a.adminName ?? "—"}: {a.resolution ?? ""} {a.amount !== null ? money(a.amount) : ""} — {a.note}
                                </div>
                              ))}
                            </>
                          )}
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
