"use client";
// src/app/dashboard/hotels/page.tsx — Hotel & guest-house verification.
// Verification (this page) is separate from the operator's role approval and from their paid
// subscription; approving a hotel never starts a subscription. The server decides and records everything.
import { Fragment, useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Status = "pending" | "verified" | "rejected" | "suspended";
type Decision = "approve" | "reject" | "suspend" | "reinstate";
interface Row {
  id: string;
  businessName: string;
  operationalType: "hotel" | "guest_house";
  status: Status;
  city: string;
  address: string;
  businessPhone: string;
  businessEmail: string | null;
  tinMasked: string | null;
  hasCommercialLicense: boolean;
  roomsCount: number;
  submittedAt: number | null;
  reviewedAt: number | null;
  verifiedAt: number | null;
  reviewNote: string | null;
  operator: { name: string | null; email: string | null; role: string; roleApproved: boolean; kycStatus: string | null; hasActiveSubscription: boolean } | null;
  events: { action: string; from: string | null; to: string; actorRole: string; actorName: string | null; note: string | null; at: number }[];
}

const when = (ms: number | null) => (ms ? new Date(ms).toLocaleString() : "—");
const BADGE: Record<Status, string> = {
  pending: styles.badgeHeld,
  verified: styles.badgeSettled,
  rejected: styles.badgeDisputed,
  suspended: styles.badgeDisputed,
};
const ACTIONS: Record<Status, { decision: Decision; label: string; needsNote: boolean }[]> = {
  pending: [
    { decision: "approve", label: "Approve", needsNote: false },
    { decision: "reject", label: "Reject", needsNote: true },
  ],
  verified: [{ decision: "suspend", label: "Suspend", needsNote: true }],
  suspended: [{ decision: "reinstate", label: "Reinstate", needsNote: true }],
  rejected: [],
};

export default function HotelsPage() {
  const [status, setStatus] = useState<Status>("pending");
  const [rows, setRows] = useState<Row[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch(`/api/hotel-verification?status=${status}`);
      const body = await res.json();
      if (body.success) setRows(body.data);
      else setError(body.error ?? "Could not load hotel applications.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, [status]);

  useEffect(() => {
    load();
  }, [load]);

  async function decide(r: Row, decision: Decision, needsNote: boolean) {
    const note = window.prompt(
      `${decision.toUpperCase()} "${r.businessName}"?\n${needsNote ? "Reason (required, kept in the audit trail):" : "Note (optional):"}`
    );
    if (note === null) return;
    setMsg("");
    try {
      const res = await adminFetch("/api/hotel-verification", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ hotelId: r.id, decision, note }),
      });
      const body = await res.json();
      setMsg(body.success ? `Done: ${body.data.status}.` : body.error ?? "The decision could not be applied.");
      if (body.success) load();
    } catch {
      setMsg("Network connection error");
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Hotels &amp; Guest Houses</h1>
          <p className={styles.subtitle}>
            A property is listed and can take bookings only after you verify it. The operator also needs an approved role and an
            active paid subscription — approving here never activates a subscription. Every decision is recorded.
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <select value={status} onChange={(e) => setStatus(e.target.value as Status)} style={{ padding: 8, borderRadius: 8 }}>
            <option value="pending">Pending review</option>
            <option value="verified">Verified</option>
            <option value="suspended">Suspended</option>
            <option value="rejected">Rejected</option>
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
                <th>Property</th>
                <th>Operator</th>
                <th>Role / subscription</th>
                <th>Submitted</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !loading && (
                <tr>
                  <td colSpan={6} className={styles.statSub}>
                    Nothing here.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <Fragment key={r.id}>
                  <tr>
                    <td>
                      {r.businessName}
                      <div className={styles.statSub}>
                        {r.operationalType === "hotel" ? "Hotel" : "Guest house"} · {r.city} · {r.roomsCount} rooms
                      </div>
                    </td>
                    <td>
                      {r.operator?.name ?? "—"}
                      <div className={styles.statSub}>{r.operator?.email ?? ""}</div>
                    </td>
                    <td style={{ fontSize: 13 }}>
                      Role approved: {r.operator?.roleApproved ? "yes" : "no"}
                      <div className={styles.statSub}>Subscription: {r.operator?.hasActiveSubscription ? "active" : "none"}</div>
                    </td>
                    <td>{when(r.submittedAt)}</td>
                    <td>
                      <span className={`${styles.badge} ${BADGE[r.status]}`}>{r.status}</span>
                    </td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      <button className={styles.actionBtn} onClick={() => setOpen(open === r.id ? null : r.id)}>
                        {open === r.id ? "Hide" : "Details"}
                      </button>
                      <div style={{ display: "flex", gap: 6, marginTop: 6 }}>
                        {ACTIONS[r.status].map((a) => (
                          <button key={a.decision} className={styles.actionBtn} onClick={() => decide(r, a.decision, a.needsNote)}>
                            {a.label}
                          </button>
                        ))}
                      </div>
                    </td>
                  </tr>
                  {open === r.id && (
                    <tr>
                      <td colSpan={6} style={{ background: "#f8fafc", fontSize: 13 }}>
                        <div>Premises: {r.address}, {r.city}</div>
                        <div>
                          Business contact: {r.businessPhone}
                          {r.businessEmail ? ` · ${r.businessEmail}` : ""}
                        </div>
                        <div>
                          TIN: {r.tinMasked ?? "not provided"} · Commercial licence: {r.hasCommercialLicense ? "on file" : "not provided"}
                        </div>
                        <div>
                          Operator identity check: {r.operator?.kycStatus ?? "—"} · Operator role: {r.operator?.role ?? "—"}
                        </div>
                        {r.reviewNote && <div>Latest note: {r.reviewNote}</div>}
                        <div className={styles.statLabel} style={{ marginTop: 8 }}>
                          History
                        </div>
                        {r.events.map((e, i) => (
                          <div key={i}>
                            {when(e.at)} — <strong>{e.action}</strong> ({e.from ?? "—"} → {e.to}) by {e.actorName ?? e.actorRole}
                            {e.note ? `: ${e.note}` : ""}
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
    </div>
  );
}
