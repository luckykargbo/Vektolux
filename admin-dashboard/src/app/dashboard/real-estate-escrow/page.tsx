"use client";
// src/app/dashboard/real-estate-escrow/page.tsx — Real Estate Escrow & Settlement Console
import { useState, useEffect, useCallback } from "react";
import {
  Building2,
  RefreshCcw,
  Clock,
  CheckCircle2,
  AlertTriangle,
  FileText,
  DollarSign,
  Compass,
  Key,
  ShieldCheck,
} from "lucide-react";
import styles from "./escrow.module.css";

interface RealEstateEscrowSummary {
  totalContracts: number;
  totalInspectionPasses: number;
  totalInEscrow: number;
  totalSettledVolume: number;
  cautionDepositsHeld: number;
  activeShortStays: number;
  activeLongLeases: number;
  activeLandMilestones: number;
  activeDisputesCount: number;
}

interface EscrowContract {
  _id: string;
  contractCode: string;
  contractType: string;
  propertyTitle?: string;
  propertyCategory?: string;
  propertyCity?: string;
  grossAmount: number;
  cautionDepositAmount: number;
  platformFeeAmount: number;
  agentCommissionAmount: number;
  netBeneficiaryExpected: number;
  releasedBeneficiaryAmount: number;
  refundedClientAmount: number;
  paymentRail: string;
  currentState: string;
  stayCheckInTimestamp?: number;
  stay24hAutoReleaseTimestamp?: number;
  createdAt: number;
}

interface InspectionPass {
  _id: string;
  qrHash: string;
  otpCode: string;
  tourFee: number;
  agentNetFee: number;
  platformFee: number;
  status: string;
  propertyTitle?: string;
  isAddressUnmasked: boolean;
  scheduledAt: number;
  createdAt: number;
}

export default function RealEstateEscrowDashboardPage() {
  const [summary, setSummary] = useState<RealEstateEscrowSummary | null>(null);
  const [contracts, setContracts] = useState<EscrowContract[]>([]);
  const [passes, setPasses] = useState<InspectionPass[]>([]);
  const [activeTab, setActiveTab] = useState<"ALL" | "PASSES" | "SHORT_STAY" | "LEASE" | "LAND">("ALL");
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [error, setError] = useState("");

  const loadData = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/real-estate-escrow");
      const data = await res.json();
      if (data.success) {
        setSummary(data.data?.summary ?? null);
        setContracts(data.data?.escrows?.contracts ?? []);
        setPasses(data.data?.escrows?.inspectionPasses ?? []);
      } else {
        setError(data.error ?? "Failed to load real estate escrow data.");
      }
    } catch (err: any) {
      setError(err?.message ?? "Network error fetching real estate escrow data.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleAction = async (action: string, payload: any) => {
    if (!confirm(`Are you sure you want to proceed with this real estate settlement action?`)) return;
    setActionLoading(payload.contractId ?? payload.passId ?? action);
    try {
      const res = await fetch("/api/real-estate-escrow", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, ...payload }),
      });
      const data = await res.json();
      if (data.success) {
        alert("Action successfully processed!");
        loadData();
      } else {
        alert(`Failed: ${data.error}`);
      }
    } catch (e: any) {
      alert(`Error: ${e.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const filteredContracts = contracts.filter((c) => {
    if (activeTab === "ALL") return true;
    if (activeTab === "SHORT_STAY") return c.contractType === "SHORT_STAY_BOOKING";
    if (activeTab === "LEASE") return c.contractType === "LONG_TERM_LEASE";
    if (activeTab === "LAND") return c.contractType === "LAND_PURCHASE_MILESTONE";
    return true;
  });

  const formatSLE = (val: number) =>
    new Intl.NumberFormat("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 2 }).format(val);

  return (
    <div className={styles.page}>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Property Escrow & Tenancy Vault</h1>
          <p className={styles.subtitle}>
            Multi-tier escrow custody for Viewing Passes (Anti-Bypass), Short-Stay 24h holds, Tenancy Caution, and Land Milestones (SLE).
          </p>
        </div>
        <button className={styles.refreshBtn} onClick={loadData} disabled={loading}>
          <RefreshCcw size={15} className={loading ? "animate-spin" : ""} />
          Refresh Vault
        </button>
      </div>

      {error && <div className={styles.badgeDanger} style={{ padding: "12px 16px" }}>{error}</div>}

      {/* Real-time Telemetry Stats Grid */}
      <div className={styles.statsGrid}>
        <div className={styles.statCard}>
          <span className={styles.statLabel}>Total In Escrow Custody</span>
          <span className={styles.statValue} style={{ color: "#2563eb" }}>
            SLE {formatSLE(summary?.totalInEscrow ?? 0)}
          </span>
          <span className={styles.statSubtext}>Active locked custody across all property contracts</span>
        </div>

        <div className={styles.statCard}>
          <span className={styles.statLabel}>Caution Deposits in Vault</span>
          <span className={styles.statValue} style={{ color: "#10b981" }}>
            SLE {formatSLE(summary?.cautionDepositsHeld ?? 0)}
          </span>
          <span className={styles.statSubtext}>Segregated tenant security deposits</span>
        </div>

        <div className={styles.statCard}>
          <span className={styles.statLabel}>Settled Volume</span>
          <span className={styles.statValue}>
            SLE {formatSLE(summary?.totalSettledVolume ?? 0)}
          </span>
          <span className={styles.statSubtext}>Disbursed rent & completed land sales</span>
        </div>

        <div className={styles.statCard}>
          <span className={styles.statLabel}>Viewing Tours (Anti-Bypass)</span>
          <span className={styles.statValue} style={{ color: "#8b5cf6" }}>
            {summary?.totalInspectionPasses ?? 0} Passes
          </span>
          <span className={styles.statSubtext}>SLE 50-100 micro-escrow viewing tickets</span>
        </div>

        <div className={styles.statCard}>
          <span className={styles.statLabel}>Active Short Stays</span>
          <span className={styles.statValue} style={{ color: "#0ea5e9" }}>
            {summary?.activeShortStays ?? 0} Stays
          </span>
          <span className={styles.statSubtext}>Protected by 24h check-in rule</span>
        </div>

        <div className={styles.statCard}>
          <span className={styles.statLabel}>Land Purchases (10/40/50)</span>
          <span className={styles.statValue} style={{ color: "#f59e0b" }}>
            {summary?.activeLandMilestones ?? 0} Parcels
          </span>
          <span className={styles.statSubtext}>OARG title & survey verification gates</span>
        </div>
      </div>

      {/* Table Section */}
      <div className={styles.tableSection}>
        <div className={styles.tableHeader}>
          <h2 className={styles.tableTitle}>Property Escrow Contracts & Viewing Passes</h2>
          <div className={styles.tabs}>
            <button
              className={`${styles.tab} ${activeTab === "ALL" ? styles.activeTab : ""}`}
              onClick={() => setActiveTab("ALL")}
            >
              All Contracts ({contracts.length})
            </button>
            <button
              className={`${styles.tab} ${activeTab === "PASSES" ? styles.activeTab : ""}`}
              onClick={() => setActiveTab("PASSES")}
            >
              Viewing Passes ({passes.length})
            </button>
            <button
              className={`${styles.tab} ${activeTab === "SHORT_STAY" ? styles.activeTab : ""}`}
              onClick={() => setActiveTab("SHORT_STAY")}
            >
              Short Stays ({contracts.filter((c) => c.contractType === "SHORT_STAY_BOOKING").length})
            </button>
            <button
              className={`${styles.tab} ${activeTab === "LEASE" ? styles.activeTab : ""}`}
              onClick={() => setActiveTab("LEASE")}
            >
              Leases ({contracts.filter((c) => c.contractType === "LONG_TERM_LEASE").length})
            </button>
            <button
              className={`${styles.tab} ${activeTab === "LAND" ? styles.activeTab : ""}`}
              onClick={() => setActiveTab("LAND")}
            >
              Land (10/40/50) ({contracts.filter((c) => c.contractType === "LAND_PURCHASE_MILESTONE").length})
            </button>
          </div>
        </div>

        <div className={styles.tableWrapper}>
          {activeTab === "PASSES" ? (
            /* Inspection Passes Table */
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>Pass Token</th>
                  <th>Property</th>
                  <th>Tour Fee</th>
                  <th>Agent Split (85%)</th>
                  <th>Platform Cut (15%)</th>
                  <th>OTP Code</th>
                  <th>Anti-Bypass Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {passes.length === 0 ? (
                  <tr>
                    <td colSpan={8} className={styles.empty}>
                      No inspection viewing passes recorded yet.
                    </td>
                  </tr>
                ) : (
                  passes.map((p) => (
                    <tr key={p._id}>
                      <td>
                        <span style={{ fontWeight: 700, color: "#0f172a" }}>{p.qrHash}</span>
                      </td>
                      <td>{p.propertyTitle ?? "Property Tour"}</td>
                      <td>SLE {formatSLE(p.tourFee)}</td>
                      <td style={{ color: "#10b981", fontWeight: 700 }}>SLE {formatSLE(p.agentNetFee)}</td>
                      <td>SLE {formatSLE(p.platformFee)}</td>
                      <td>
                        <code style={{ background: "#f1f5f9", padding: "2px 6px", borderRadius: 4, fontWeight: 700 }}>
                          {p.otpCode}
                        </code>
                      </td>
                      <td>
                        <span
                          className={`${styles.badge} ${
                            p.status === "FULLY_SETTLED" ? styles.badgeSuccess : styles.badgeWarning
                          }`}
                        >
                          {p.status === "FULLY_SETTLED" ? "Verified & Settled" : "Tour In Progress"}
                        </span>
                      </td>
                      <td>
                        {p.status !== "FULLY_SETTLED" && (
                          <button
                            className={`${styles.actionBtn} ${styles.actionBtnPrimary}`}
                            disabled={actionLoading === p._id}
                            onClick={() =>
                              handleAction("verifyPass", {
                                passId: p._id,
                                qrHash: p.qrHash,
                                otpCode: p.otpCode,
                              })
                            }
                          >
                            Verify & Disburse
                          </button>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          ) : (
            /* Master Escrow Contracts Table */
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>Contract Code</th>
                  <th>Property</th>
                  <th>Type</th>
                  <th>Gross Custody</th>
                  <th>Caution Deposit</th>
                  <th>Net Disbursed</th>
                  <th>State</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredContracts.length === 0 ? (
                  <tr>
                    <td colSpan={8} className={styles.empty}>
                      No real estate escrow contracts found for this filter.
                    </td>
                  </tr>
                ) : (
                  filteredContracts.map((c) => (
                    <tr key={c._id}>
                      <td>
                        <span style={{ fontWeight: 700, color: "#0f172a" }}>{c.contractCode}</span>
                        <div style={{ fontSize: 11, color: "#94a3b8" }}>{c.paymentRail}</div>
                      </td>
                      <td>
                        <div style={{ fontWeight: 600 }}>{c.propertyTitle ?? "Property"}</div>
                        <div style={{ fontSize: 11, color: "#64748b" }}>{c.propertyCity ?? "Freetown"}</div>
                      </td>
                      <td>
                        <span
                          className={`${styles.badge} ${
                            c.contractType === "SHORT_STAY_BOOKING"
                              ? styles.badgeInfo
                              : c.contractType === "LONG_TERM_LEASE"
                              ? styles.badgeNeutral
                              : styles.badgeWarning
                          }`}
                        >
                          {c.contractType.replace("_", " ")}
                        </span>
                      </td>
                      <td style={{ fontWeight: 700 }}>SLE {formatSLE(c.grossAmount)}</td>
                      <td style={{ color: "#10b981", fontWeight: 600 }}>
                        {c.cautionDepositAmount > 0 ? `SLE ${formatSLE(c.cautionDepositAmount)}` : "—"}
                      </td>
                      <td>SLE {formatSLE(c.releasedBeneficiaryAmount)}</td>
                      <td>
                        <span
                          className={`${styles.badge} ${
                            c.currentState === "FULLY_SETTLED"
                              ? styles.badgeSuccess
                              : c.currentState === "UNDER_ARBITRATION"
                              ? styles.badgeDanger
                              : styles.badgeInfo
                          }`}
                        >
                          {c.currentState}
                        </span>
                      </td>
                      <td>
                        <div className={styles.actionsCell}>
                          {c.contractType === "SHORT_STAY_BOOKING" && c.currentState === "CHECKED_IN" && (
                            <button
                              className={`${styles.actionBtn} ${styles.actionBtnPrimary}`}
                              disabled={actionLoading === c._id}
                              onClick={() => handleAction("releaseStay24h", { contractId: c._id })}
                            >
                              Release Host (24h)
                            </button>
                          )}
                          {c.cautionDepositAmount > 0 && c.currentState !== "FULLY_SETTLED" && (
                            <button
                              className={styles.actionBtn}
                              disabled={actionLoading === c._id}
                              onClick={() => handleAction("refundCaution", { contractId: c._id })}
                            >
                              Refund Caution
                            </button>
                          )}
                          {c.contractType === "LAND_PURCHASE_MILESTONE" && c.currentState !== "FULLY_SETTLED" && (
                            <button
                              className={`${styles.actionBtn} ${styles.actionBtnPrimary}`}
                              disabled={actionLoading === c._id}
                              onClick={() =>
                                handleAction("releaseLandMilestone", {
                                  contractId: c._id,
                                  milestoneIndex: c.releasedBeneficiaryAmount === 0 ? 1 : 2,
                                  proofUrls: ["https://storage.vektolux.sl/cadastral/verified.pdf"],
                                })
                              }
                            >
                              Release Milestone
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
