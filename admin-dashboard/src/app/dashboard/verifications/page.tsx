"use client";
// src/app/dashboard/verifications/page.tsx — Agent Verification Queue
import { useEffect, useState, useCallback } from "react";
import type { AdminSession, VerificationEntry, VerificationStatus } from "@/lib/types";
import styles from "./verifications.module.css";

export default function VerificationsPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [entries, setEntries] = useState<VerificationEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<VerificationStatus>("pending");
  const [actionId, setActionId] = useState<string | null>(null);
  const [rejectModal, setRejectModal] = useState<{ entry: VerificationEntry } | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    const raw = sessionStorage.getItem("adminSession");
    if (raw) setSession(JSON.parse(raw));
  }, []);

  const loadQueue = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    setError("");
    try {
      const res = await fetch(
        `/api/verifications?adminId=${session.user.id}&sessionToken=${session.user.sessionToken}&status=${filter}`
      );
      const data = await res.json();
      if (data.success) {
        setEntries(data.data ?? []);
      } else {
        setError(data.error ?? "Failed to load queue.");
      }
    } catch (e: any) {
      setError("Network error. Is the Convex backend reachable?");
    }
    setLoading(false);
  }, [session, filter]);

  useEffect(() => { loadQueue(); }, [loadQueue]);

  async function handleApprove(entry: VerificationEntry) {
    if (!session) return;
    setActionId(entry.userId);
    try {
      const res = await fetch("/api/verifications", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "approve",
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          agentId: entry.userId,
        }),
      });
      const data = await res.json();
      if (data.success) {
        await loadQueue();
      } else {
        alert("Approval failed: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error during approval.");
    }
    setActionId(null);
  }

  async function handleRejectSubmit() {
    if (!rejectModal || !session) return;
    const trimmedReason = rejectReason.trim();
    if (!trimmedReason) { alert("Please enter a rejection reason."); return; }

    setActionId(rejectModal.entry.userId);
    try {
      const res = await fetch("/api/verifications", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "reject",
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          agentId: rejectModal.entry.userId,
          reason: trimmedReason,
        }),
      });
      const data = await res.json();
      if (data.success) {
        setRejectModal(null);
        setRejectReason("");
        await loadQueue();
      } else {
        alert("Rejection failed: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error during rejection.");
    }
    setActionId(null);
  }

  const filterOptions: { value: VerificationStatus; label: string }[] = [
    { value: "pending", label: "⏳ Pending" },
    { value: "approved", label: "✅ Approved" },
    { value: "rejected", label: "❌ Rejected" },
    { value: "all", label: "📋 All" },
  ];

  function formatDate(ts?: number) {
    if (!ts) return "—";
    return new Date(ts).toLocaleString("en-GB", {
      day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit",
    });
  }

  function statusBadge(status: string) {
    const map: Record<string, { bg: string; color: string; label: string }> = {
      pending:  { bg: "rgba(245,158,11,0.12)", color: "#f59e0b", label: "⏳ PENDING" },
      approved: { bg: "rgba(16,185,129,0.12)", color: "#10b981", label: "✅ APPROVED" },
      rejected: { bg: "rgba(239,68,68,0.12)",  color: "#ef4444", label: "❌ REJECTED" },
    };
    const s = map[status] ?? { bg: "#334155", color: "#94a3b8", label: status.toUpperCase() };
    return (
      <span style={{ background: s.bg, color: s.color, border: `1px solid ${s.color}30`, borderRadius: 100, padding: "3px 10px", fontSize: 11, fontWeight: 700, letterSpacing: 0.5 }}>
        {s.label}
      </span>
    );
  }

  return (
    <div>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Verification Queue</h1>
          <p className={styles.subtitle}>
            Review agent and merchant identity documents. Approve or reject applications.
          </p>
        </div>
        <button onClick={() => loadQueue()} className={styles.refreshBtn} disabled={loading}>
          {loading ? "Loading…" : "↻ Refresh"}
        </button>
      </div>

      {/* Filter Tabs */}
      <div className={styles.filterTabs}>
        {filterOptions.map((opt) => (
          <button
            key={opt.value}
            onClick={() => setFilter(opt.value)}
            className={`${styles.filterTab} ${filter === opt.value ? styles.filterTabActive : ""}`}
          >
            {opt.label}
          </button>
        ))}
      </div>

      {/* Error */}
      {error && <div className={styles.errorBox}>⚠️ {error}</div>}

      {/* Loading */}
      {loading && !error && (
        <div className={styles.loadingBox}>
          <div className={styles.spinner} />
          <span>Loading verification queue…</span>
        </div>
      )}

      {/* Empty */}
      {!loading && !error && entries.length === 0 && (
        <div className={styles.emptyBox}>
          <div className={styles.emptyIcon}>📭</div>
          <div className={styles.emptyText}>No {filter === "all" ? "" : filter} submissions found.</div>
        </div>
      )}

      {/* Entry Cards */}
      {!loading && entries.length > 0 && (
        <div className={styles.entries}>
          {entries.map((entry) => (
            <div key={entry.userId} className={styles.entryCard}>
              <div className={styles.entryTop}>
                {/* Avatar */}
                <div className={styles.avatar}>
                  {(entry.name ?? "?").charAt(0).toUpperCase()}
                </div>

                {/* Info */}
                <div className={styles.entryInfo}>
                  <div className={styles.entryName}>{entry.name}</div>
                  <div className={styles.entryMeta}>
                    {entry.email && <span>📧 {entry.email}</span>}
                    {entry.phone && <span>📱 {entry.phone}</span>}
                  </div>
                  <div className={styles.entryMeta}>
                    <span>🏢 {entry.businessName}</span>
                    <span>🆔 TIN: {entry.tinNumber}</span>
                  </div>
                </div>

                {/* Status */}
                <div className={styles.entryStatus}>
                  {statusBadge(entry.verificationStatus)}
                </div>
              </div>

              {/* Dates */}
              <div className={styles.entryDates}>
                <span>Submitted: <strong>{formatDate(entry.createdAt)}</strong></span>
                {entry.verifiedAt && (
                  <span>Reviewed: <strong>{formatDate(entry.verifiedAt)}</strong></span>
                )}
                {entry.rejectionReason && (
                  <span className={styles.rejectReason}>
                    Reason: "{entry.rejectionReason}"
                  </span>
                )}
              </div>

              {/* Document & Actions */}
              <div className={styles.entryActions}>
                {entry.documentUrl ? (
                  <a
                    href={entry.documentUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={styles.viewDocBtn}
                  >
                    📄 View Document
                  </a>
                ) : (
                  <span className={styles.noDoc}>No document uploaded</span>
                )}

                {entry.verificationStatus === "pending" && (
                  <div className={styles.actionBtns}>
                    <button
                      onClick={() => handleApprove(entry)}
                      disabled={actionId === entry.userId}
                      className={styles.approveBtn}
                    >
                      {actionId === entry.userId ? "…" : "✅ Approve"}
                    </button>
                    <button
                      onClick={() => { setRejectModal({ entry }); setRejectReason(""); }}
                      disabled={actionId === entry.userId}
                      className={styles.rejectBtn}
                    >
                      ❌ Reject
                    </button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Reject Modal */}
      {rejectModal && (
        <div className={styles.modalOverlay} onClick={() => setRejectModal(null)}>
          <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
            <h2 className={styles.modalTitle}>Reject Verification</h2>
            <p className={styles.modalSubtitle}>
              Rejecting application from <strong>{rejectModal.entry.name}</strong> ({rejectModal.entry.businessName})
            </p>
            <div className={styles.field}>
              <label className={styles.label}>Rejection Reason (required)</label>
              <textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                className={styles.textarea}
                placeholder="e.g. Documents are blurry, TIN number does not match records, incomplete application..."
                rows={4}
              />
            </div>
            <div className={styles.modalActions}>
              <button onClick={() => setRejectModal(null)} className={styles.cancelBtn}>
                Cancel
              </button>
              <button
                onClick={handleRejectSubmit}
                disabled={!rejectReason.trim() || actionId !== null}
                className={styles.confirmRejectBtn}
              >
                {actionId ? "Rejecting…" : "Confirm Rejection"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
