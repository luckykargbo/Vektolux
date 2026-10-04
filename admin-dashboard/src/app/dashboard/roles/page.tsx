"use client";
// src/app/dashboard/roles/page.tsx — Business role applications (Agent, Owner, Car Dealer, Hotel)
import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Status = "pending" | "approved" | "rejected" | "suspended";
type Decision = "approve" | "reject" | "suspend";

interface Row {
  id: string;
  userId: string;
  userName: string;
  userEmail: string | null;
  currentRole: string | null;
  identityStatus: string;
  targetRole: string;
  targetRoleLabel: string;
  businessName: string | null;
  tinNumber: string | null;
  licenseNumber: string | null;
  documentCount: number;
  status: Status;
  reviewNotes: string | null;
  reviewedAt: number | null;
  submittedAt: number;
}

const when = (ms: number | null) => (ms ? new Date(ms).toLocaleString() : "—");
const BADGE: Record<Status, string> = {
  pending: styles.badgeHeld,
  approved: styles.badgeSettled,
  rejected: styles.badgeDisputed,
  suspended: styles.badgeDisputed,
};

export default function RolesPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [filter, setFilter] = useState<"" | Status>("pending");
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch(`/api/roles${filter ? `?status=${filter}` : ""}`);
      const body = await res.json();
      if (body.success) setRows(body.data ?? []);
      else setError(body.error ?? "Could not load applications.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, [filter]);

  useEffect(() => {
    load();
  }, [load]);

  async function decide(r: Row, decision: Decision) {
    let notes: string | undefined;
    if (decision === "approve") {
      const extra =
        r.targetRole === "dealer" || r.targetRole === "merchant"
          ? r.currentRole === "agent"
            ? " This adds Car Dealer to the existing Real Estate Agent role."
            : ""
          : "";
      if (!window.confirm(`Approve ${r.userName} as ${r.targetRoleLabel}?${extra}`)) return;
      const n = window.prompt("Optional note for the applicant:");
      if (n === null) return;
      notes = n.trim() || undefined;
    } else {
      const n = window.prompt(`${decision === "reject" ? "Reject" : "Suspend"} ${r.userName}'s ${r.targetRoleLabel} role. Reason (required, shown to the user):`);
      if (n === null) return;
      notes = n.trim();
    }
    setBusy(r.id);
    setMsg("");
    try {
      const res = await adminFetch("/api/roles", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ applicationId: r.id, decision, ...(notes ? { notes } : {}) }),
      });
      const body = await res.json();
      setMsg(body.success ? `Application ${body.data?.status ?? decision}.` : body.error ?? "Could not save the decision.");
      if (body.success) load();
    } catch {
      setMsg("Network connection error");
    }
    setBusy(null);
  }

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Business Roles</h1>
          <p className={styles.subtitle}>
            Real Estate Agent, Real Estate Owner, Car Dealer and Hotel applications. A role is granted only here. Approving Car Dealer for
            an approved Real Estate Agent adds it to the same account (&ldquo;Real Estate Agent &amp; Car Dealer&rdquo;).
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <select value={filter} onChange={(e) => setFilter(e.target.value as "" | Status)} style={{ padding: 8, borderRadius: 8 }}>
            <option value="pending">Pending</option>
            <option value="approved">Approved</option>
            <option value="rejected">Rejected</option>
            <option value="suspended">Suspended</option>
            <option value="">All</option>
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
                <th>Applicant</th>
                <th>Applying for</th>
                <th>Business</th>
                <th>Identity</th>
                <th>Status</th>
                <th>Submitted</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !loading && (
                <tr>
                  <td colSpan={7} className={styles.statSub}>
                    No applications.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>
                    {r.userName}
                    <div className={styles.statSub}>
                      {r.userEmail ?? ""} · now {r.currentRole ?? "—"}
                    </div>
                  </td>
                  <td>{r.targetRoleLabel}</td>
                  <td>
                    {r.businessName ?? "—"}
                    <div className={styles.statSub}>
                      {r.tinNumber ? `TIN ${r.tinNumber}` : ""} {r.licenseNumber ? `· Licence ${r.licenseNumber}` : ""} · {r.documentCount} document
                      {r.documentCount === 1 ? "" : "s"}
                    </div>
                  </td>
                  <td>{r.identityStatus}</td>
                  <td>
                    <span className={`${styles.badge} ${BADGE[r.status]}`}>{r.status}</span>
                    {r.reviewNotes && <div className={styles.statSub}>{r.reviewNotes}</div>}
                  </td>
                  <td>{when(r.submittedAt)}</td>
                  <td style={{ whiteSpace: "nowrap" }}>
                    {r.status === "pending" && (
                      <>
                        <button className={styles.actionBtn} disabled={busy === r.id} onClick={() => decide(r, "approve")}>
                          Approve
                        </button>{" "}
                        <button className={styles.actionBtn} disabled={busy === r.id} onClick={() => decide(r, "reject")}>
                          Reject…
                        </button>
                      </>
                    )}
                    {r.status === "approved" && (
                      <button className={styles.actionBtn} disabled={busy === r.id} onClick={() => decide(r, "suspend")}>
                        Suspend…
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
