"use client";
// src/app/dashboard/refund-recovery/page.tsx — Refunds after payout: reversals and recovery cases
import { Fragment, useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Status = "completed" | "pending_recovery" | "recovered" | "platform_covered" | "written_off";
type Action = "retry" | "platform_covered" | "written_off" | "lift_protection" | "restore_protection";
interface Person {
  name: string;
  email: string | null;
}
interface Reversal {
  id: string;
  status: Status;
  currency: string;
  referenceType: string;
  referenceId: string;
  buyer: Person | null;
  recipient: Person | null;
  originalAmount: number;
  platformFeeReversed: number;
  recipientNetOwed: number;
  recoveredFromRecipient: number;
  platformCoveredAmount: number;
  writtenOffAmount: number;
  refundedToBuyer: number;
  outstandingAmount: number;
  protectionActive: boolean;
  withdrawalProtection?: "active" | "lifted";
  reason: string;
  createdAt: number;
  createdByName: string | null;
  closedAt?: number;
  closedByName: string | null;
  closeNote?: string;
  originalRelease: { transactionCode: string | null; amount: number; platformFee: number; referenceType: string | null; referenceId: string | null; releasedAt: number | null } | null;
  events: { action: string; amount: number; transactionCode: string | null; ledgerCode: string | null; note: string | null; at: number; actorName: string | null }[];
}
interface Release {
  id: string;
  transactionCode: string | null;
  amount: number;
  platformFee: number;
  currency: string;
  referenceType: string | null;
  referenceId: string | null;
  releasedAt: number | null;
  buyerName: string | null;
  recipientName: string | null;
  reversalId: string | null;
}

const when = (ms: number | null | undefined) => (ms ? new Date(ms).toLocaleString() : "—");
const money = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const LABEL: Record<Status, string> = {
  completed: "Fully reversed",
  pending_recovery: "Pending recovery",
  recovered: "Recovered",
  platform_covered: "Platform covered",
  written_off: "Written off",
};
const BADGE: Record<Status, string> = {
  completed: styles.badgeSettled,
  pending_recovery: styles.badgeHeld,
  recovered: styles.badgeSettled,
  platform_covered: styles.badgeReleased,
  written_off: styles.badgeDisputed,
};
const ACTION_TEXT: Record<Action, string> = {
  retry: "Retry recovery from the recipient's current available balance",
  platform_covered: "Platform covers the remaining amount (credited to the buyer from platform revenue)",
  written_off: "Write off the remaining amount (the buyer is NOT credited further)",
  lift_protection: "Lift the protection (the recipient can use the reserved funds)",
  restore_protection: "Restore the protection",
};

export default function RefundRecoveryPage() {
  const [reversals, setReversals] = useState<Reversal[]>([]);
  const [releases, setReleases] = useState<Release[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch("/api/refund-recovery");
      const body = await res.json();
      if (body.success) {
        setReversals(body.data.reversals);
        setReleases(body.data.releases);
      } else setError(body.error ?? "Could not load refund recovery data.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function post(payload: Record<string, unknown>, done: string) {
    setBusy(true);
    setMsg("");
    try {
      const res = await adminFetch("/api/refund-recovery", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const body = await res.json();
      setMsg(body.success ? done : body.error ?? "The action could not be completed.");
      if (body.success) load();
    } catch {
      setMsg("Network connection error");
    }
    setBusy(false);
  }

  function act(r: Reversal, action: Action) {
    const note = window.prompt(`${ACTION_TEXT[action]}.\nOutstanding: ${r.currency} ${money(r.outstandingAmount)}.\n\nAdmin note (required, audited):`);
    if (note === null) return;
    post({ action, reversalId: r.id, note }, "Done.");
  }

  function reverse(rel: Release) {
    const note = window.prompt(
      `Reverse payout ${rel.transactionCode ?? rel.id} (${rel.currency} ${money(rel.amount)} to ${rel.recipientName ?? "recipient"})?\n` +
        "The fee is reversed from platform revenue and the recipient's payout is recovered from their available balance (never below zero); any shortfall opens a recovery case.\n\nReason (required, audited):"
    );
    if (note === null) return;
    post({ action: "reverse", releaseTransactionId: rel.id, note }, "Payout reversed.");
  }

  const openCases = reversals.filter((r) => r.status === "pending_recovery");

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Refund Recovery</h1>
          <p className={styles.subtitle}>
            Refunds after a payout create new reversal entries — the original payout is never edited. Recipients are never taken
            below zero; any shortfall stays open here, and the owed amount is protected from their withdrawals, transfers and
            payments until it is resolved.
          </p>
        </div>
        <button className={styles.refreshBtn} onClick={load} disabled={loading}>
          <RefreshCcw size={16} /> Refresh
        </button>
      </div>

      {error && <p style={{ color: "#dc2626" }}>{error}</p>}
      {msg && <p style={{ fontSize: 14 }}>{msg}</p>}

      <div className={styles.statsGrid}>
        <div className={styles.statCard}>
          <div className={styles.statLabel}>Open recovery cases</div>
          <div className={styles.statValue}>{openCases.length}</div>
          <div className={styles.statSub}>pending recovery</div>
        </div>
        <div className={styles.statCard}>
          <div className={styles.statLabel}>Outstanding</div>
          <div className={styles.statValue}>{money(openCases.reduce((s, r) => s + r.outstandingAmount, 0))}</div>
          <div className={styles.statSub}>owed by recipients</div>
        </div>
      </div>

      <div className={styles.tableCard} style={{ marginBottom: 20 }}>
        <div className={styles.tableHeader}>
          <div className={styles.tableTitle}>Reversals &amp; recovery cases</div>
        </div>
        <div style={{ overflowX: "auto" }}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Recovery ID</th>
                <th>Original transaction</th>
                <th>Recipient</th>
                <th>Owed</th>
                <th>Recovered</th>
                <th>Remaining</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {reversals.length === 0 && !loading && (
                <tr>
                  <td colSpan={8} className={styles.statSub}>
                    No reversals yet.
                  </td>
                </tr>
              )}
              {reversals.map((r) => (
                <Fragment key={r.id}>
                  <tr>
                    <td style={{ fontFamily: "monospace", fontSize: 12 }}>{r.id}</td>
                    <td style={{ fontSize: 13 }}>
                      {r.originalRelease?.transactionCode ?? "—"}
                      <div className={styles.statSub}>
                        {r.referenceType} · {r.currency} {money(r.originalAmount)} (fee {money(r.platformFeeReversed)}) · {when(r.originalRelease?.releasedAt)}
                      </div>
                    </td>
                    <td>
                      {r.recipient?.name ?? "—"}
                      <div className={styles.statSub}>buyer: {r.buyer?.name ?? "—"}</div>
                    </td>
                    <td>{money(r.recipientNetOwed)}</td>
                    <td>{money(r.recoveredFromRecipient)}</td>
                    <td>
                      {money(r.outstandingAmount)}
                      {r.status === "pending_recovery" && (
                        <div className={styles.statSub}>{r.protectionActive ? "protected" : "protection lifted"}</div>
                      )}
                    </td>
                    <td>
                      <span className={`${styles.badge} ${BADGE[r.status]}`}>{LABEL[r.status]}</span>
                    </td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      <button className={styles.actionBtn} onClick={() => setOpen(open === r.id ? null : r.id)}>
                        {open === r.id ? "Hide" : "Audit trail"}
                      </button>
                      {r.status === "pending_recovery" && (
                        <div style={{ display: "flex", gap: 6, marginTop: 6, flexWrap: "wrap" }}>
                          <button className={`${styles.actionBtn} ${styles.actionBtnPrimary}`} disabled={busy} onClick={() => act(r, "retry")}>
                            Retry
                          </button>
                          <button className={styles.actionBtn} disabled={busy} onClick={() => act(r, "platform_covered")}>
                            Platform cover
                          </button>
                          <button className={styles.actionBtn} disabled={busy} onClick={() => act(r, "written_off")}>
                            Write off
                          </button>
                          <button
                            className={styles.actionBtn}
                            disabled={busy}
                            onClick={() => act(r, r.protectionActive ? "lift_protection" : "restore_protection")}
                          >
                            {r.protectionActive ? "Lift protection" : "Restore protection"}
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                  {open === r.id && (
                    <tr>
                      <td colSpan={8} style={{ background: "#f8fafc", fontSize: 13 }}>
                        <div>
                          Opened {when(r.createdAt)} by {r.createdByName ?? "—"}: {r.reason}
                        </div>
                        <div>
                          Refunded to buyer {money(r.refundedToBuyer)} · platform covered {money(r.platformCoveredAmount)} · written off{" "}
                          {money(r.writtenOffAmount)}
                        </div>
                        {r.closedAt && (
                          <div>
                            Closed {when(r.closedAt)} by {r.closedByName ?? "—"}: {r.closeNote}
                          </div>
                        )}
                        <div className={styles.statLabel} style={{ marginTop: 8 }}>
                          Events
                        </div>
                        {r.events.map((e, i) => (
                          <div key={i} style={{ padding: "2px 0" }}>
                            {when(e.at)} — <strong>{e.action}</strong> {money(e.amount)} by {e.actorName ?? "—"}
                            {e.transactionCode ? ` · tx ${e.transactionCode}` : ""}
                            {e.ledgerCode ? ` · ledger ${e.ledgerCode}` : ""}
                            {e.note ? ` — ${e.note}` : ""}
                          </div>
                        ))}
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className={styles.tableCard}>
        <div className={styles.tableHeader}>
          <div className={styles.tableTitle}>Recent payouts (escrow releases)</div>
        </div>
        <div style={{ overflowX: "auto" }}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Released</th>
                <th>Transaction</th>
                <th>Reference</th>
                <th>Buyer → Recipient</th>
                <th>Amount</th>
                <th>Platform fee</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {releases.length === 0 && !loading && (
                <tr>
                  <td colSpan={7} className={styles.statSub}>
                    No payouts yet.
                  </td>
                </tr>
              )}
              {releases.map((rel) => (
                <tr key={rel.id}>
                  <td>{when(rel.releasedAt)}</td>
                  <td style={{ fontFamily: "monospace", fontSize: 12 }}>{rel.transactionCode ?? rel.id}</td>
                  <td style={{ fontSize: 13 }}>
                    {rel.referenceType} · {rel.referenceId}
                  </td>
                  <td>
                    {rel.buyerName ?? "—"} → {rel.recipientName ?? "—"}
                  </td>
                  <td>
                    {rel.currency} {money(rel.amount)}
                  </td>
                  <td>{money(rel.platformFee)}</td>
                  <td>
                    {rel.reversalId ? (
                      <span className={styles.statSub}>Reversed</span>
                    ) : (
                      <button className={styles.actionBtn} disabled={busy} onClick={() => reverse(rel)}>
                        Reverse (refund)
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
