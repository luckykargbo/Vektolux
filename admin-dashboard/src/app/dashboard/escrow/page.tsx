"use client";
// src/app/dashboard/escrow/page.tsx — Vehicle Escrow & Settlement Console
import { useState, useEffect, useCallback } from "react";
import {
  ShieldCheck,
  RefreshCcw,
  Clock,
  CheckCircle2,
  AlertTriangle,
  FileText,
  DollarSign,
  Car,
  User,
  ArrowRight,
} from "lucide-react";
import styles from "./escrow.module.css";

interface EscrowSummary {
  totalOrders: number;
  totalInEscrow: number;
  totalSettledVolume: number;
  activeRentalCount: number;
  pendingInspectionCount: number;
  disputedCount: number;
}

interface EscrowOrder {
  _id: string;
  orderCode: string;
  orderType: string;
  vehicleTitle?: string;
  vehicleCategory?: string;
  grossEscrowAmount: number;
  baseRentalAmount: number;
  refundableDepositAmount: number;
  split60ReleasedAmount: number;
  split40ReleasedAmount: number;
  depositRefundedAmount: number;
  depositDamageDeductedAmount: number;
  status: string;
  purchaseStage?: string;
  createdAt: number;
}

export default function EscrowDashboardPage() {
  const [summary, setSummary] = useState<EscrowSummary | null>(null);
  const [orders, setOrders] = useState<EscrowOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [error, setError] = useState("");

  const loadData = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/escrow");
      const data = await res.json();
      if (data.success) {
        setSummary(data.data?.summary ?? null);
        setOrders(data.data?.orders ?? []);
      } else {
        setError(data.error ?? "Failed to fetch escrow data");
      }
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  async function handleAction(action: string, escrowOrderId: string, extra?: any) {
    if (!confirm(`Are you sure you want to execute ${action} for order ${escrowOrderId}?`)) return;
    setActionLoading(escrowOrderId);
    try {
      const res = await fetch("/api/escrow", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, escrowOrderId, ...extra }),
      });
      const data = await res.json();
      if (data.success) {
        alert("Operation successful!");
        loadData();
      } else {
        alert("Action failed: " + (data.error ?? "Unknown error"));
      }
    } catch (e: any) {
      alert("Network error: " + e.message);
    }
    setActionLoading(null);
  }

  function getStatusBadge(status: string) {
    switch (status) {
      case "HELD_IN_ESCROW":
        return <span className={`${styles.badge} ${styles.badgeHeld}`}><Clock size={12} /> Held in Escrow</span>;
      case "PARTIALLY_RELEASED":
        return <span className={`${styles.badge} ${styles.badgeReleased}`}><ArrowRight size={12} /> 60% Released</span>;
      case "SETTLED":
        return <span className={`${styles.badge} ${styles.badgeSettled}`}><CheckCircle2 size={12} /> Settled (100%)</span>;
      case "DISPUTED":
        return <span className={`${styles.badge} ${styles.badgeDisputed}`}><AlertTriangle size={12} /> Disputed</span>;
      default:
        return <span className={styles.badge}>{status}</span>;
    }
  }

  return (
    <div className={styles.page}>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Vehicle Escrow & Settlement Engine</h1>
          <p className={styles.subtitle}>
            Live balance custody, 60/40 milestone dispatches, digital inspection sign-offs, and SLRSA title audits.
          </p>
        </div>
        <button onClick={loadData} className={styles.refreshBtn} disabled={loading}>
          <RefreshCcw size={15} /> Refresh Ledgers
        </button>
      </div>

      {error && (
        <div style={{ padding: "12px 16px", background: "#fee2e2", color: "#991b1b", borderRadius: "8px", fontSize: "13px" }}>
          {error}
        </div>
      )}

      {/* Metrics Cards */}
      <div className={styles.statsGrid}>
        <div className={styles.statCard}>
          <span className={styles.statLabel}>Total Locked in Escrow</span>
          <span className={styles.statValue}>SLE {summary ? summary.totalInEscrow.toLocaleString(undefined, { minimumFractionDigits: 2 }) : "0.00"}</span>
          <span className={styles.statSub}>Active Custody Liability</span>
        </div>
        <div className={styles.statCard}>
          <span className={styles.statLabel}>Lifetime Settled Volume</span>
          <span className={styles.statValue}>SLE {summary ? summary.totalSettledVolume.toLocaleString(undefined, { minimumFractionDigits: 2 }) : "0.00"}</span>
          <span className={styles.statSub}>100% Cleared Transactions</span>
        </div>
        <div className={styles.statCard}>
          <span className={styles.statLabel}>Active Fleet Contracts</span>
          <span className={styles.statValue}>{summary?.activeRentalCount ?? 0}</span>
          <span className={styles.statSub}>Rentals & Haulage Orders</span>
        </div>
        <div className={styles.statCard}>
          <span className={styles.statLabel}>Disputed Orders</span>
          <span className={styles.statValue} style={{ color: (summary?.disputedCount ?? 0) > 0 ? "#dc2626" : "#0f172a" }}>
            {summary?.disputedCount ?? 0}
          </span>
          <span className={styles.statSub}>Under Damage Adjudication</span>
        </div>
      </div>

      {/* Live Escrow Contracts Table */}
      <div className={styles.tableCard}>
        <div className={styles.tableHeader}>
          <h2 className={styles.tableTitle}>Active & Historical Escrow Contracts</h2>
          <span style={{ fontSize: "12px", color: "#64748b" }}>{orders.length} Total Contracts</span>
        </div>

        {orders.length === 0 && !loading ? (
          <div className={styles.emptyState}>
            <ShieldCheck size={36} style={{ color: "#94a3b8", margin: "0 auto 12px auto" }} />
            <p>No escrow contracts found. Once clients initiate vehicle rentals or purchases, they will appear here in real-time.</p>
          </div>
        ) : (
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Order Code</th>
                <th>Type</th>
                <th>Vehicle</th>
                <th>Gross Escrow</th>
                <th>Milestone Payouts</th>
                <th>Deposit</th>
                <th>Status</th>
                <th>Admin Actions</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((o) => (
                <tr key={o._id}>
                  <td>
                    <span className={styles.orderCode}>{o.orderCode}</span>
                    <div style={{ fontSize: "11px", color: "#94a3b8" }}>
                      {new Date(o.createdAt).toLocaleDateString()}
                    </div>
                  </td>
                  <td>
                    <span style={{ fontWeight: 600, fontSize: "12px" }}>
                      {o.orderType === "VEHICLE_RENTAL" ? "Rental (60/40)" : "Purchase (SLRSA)"}
                    </span>
                  </td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                      <Car size={14} style={{ color: "#64748b" }} />
                      <span style={{ fontWeight: 600 }}>{o.vehicleTitle ?? "Commercial Vehicle"}</span>
                    </div>
                    <div style={{ fontSize: "11px", color: "#64748b" }}>{o.vehicleCategory}</div>
                  </td>
                  <td>
                    <span style={{ fontWeight: 700 }}>SLE {o.grossEscrowAmount.toLocaleString()}</span>
                  </td>
                  <td>
                    <div style={{ fontSize: "11px", color: "#0f172a" }}>
                      <strong>60%:</strong> SLE {o.split60ReleasedAmount.toLocaleString()}
                    </div>
                    <div style={{ fontSize: "11px", color: "#64748b" }}>
                      <strong>40%:</strong> SLE {o.split40ReleasedAmount.toLocaleString()}
                    </div>
                  </td>
                  <td>
                    <div style={{ fontSize: "11px", color: "#059669", fontWeight: 600 }}>
                      SLE {o.refundableDepositAmount.toLocaleString()}
                    </div>
                    {o.depositDamageDeductedAmount > 0 && (
                      <div style={{ fontSize: "10px", color: "#dc2626" }}>
                        -SLE {o.depositDamageDeductedAmount} dmg
                      </div>
                    )}
                  </td>
                  <td>{getStatusBadge(o.status)}</td>
                  <td>
                    <div style={{ display: "flex", gap: "6px", flexWrap: "wrap" }}>
                      {o.status === "HELD_IN_ESCROW" && (
                        <button
                          className={`${styles.actionBtn} ${styles.actionBtnPrimary}`}
                          onClick={() => handleAction("release60", o._id)}
                          disabled={actionLoading === o._id}
                        >
                          Release 60%
                        </button>
                      )}
                      {(o.status === "PARTIALLY_RELEASED" || o.status === "POST_INSPECTION_PENDING") && (
                        <button
                          className={`${styles.actionBtn} ${styles.actionBtnEmerald}`}
                          onClick={() => handleAction("settleReturn", o._id)}
                          disabled={actionLoading === o._id}
                        >
                          Settle Return
                        </button>
                      )}
                      {o.orderType === "VEHICLE_PURCHASE" && o.purchaseStage === "SLRSA_DOCS_SUBMITTED" && (
                        <button
                          className={`${styles.actionBtn} ${styles.actionBtnEmerald}`}
                          onClick={() => handleAction("confirmSlrsa", o._id, { verificationNotes: "SLRSA Title verified by Admin" })}
                          disabled={actionLoading === o._id}
                        >
                          Verify SLRSA
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
