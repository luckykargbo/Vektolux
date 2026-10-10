"use client";

import React, { useState, useEffect } from "react";
import styles from "./payments.module.css";
import {
  CreditCard,
  Settings,
  CheckCircle2,
  XCircle,
  DollarSign,
  Clock,
  RefreshCw,
  Zap,
  Shield,
  AlertCircle
} from "lucide-react";

import { adminFetch } from "@/lib/adminSession";

export default function PaymentsPage() {
  const [paymentMethods, setPaymentMethods] = useState<any[]>([]);
  const [claims, setClaims] = useState<any[]>([]);
  const [loadingMethods, setLoadingMethods] = useState(true);
  const [loadingClaims, setLoadingClaims] = useState(true);
  const [alert, setAlert] = useState<{ type: "success" | "error"; message: string } | null>(null);

  // Rejection Modal State
  const [rejectModalOpen, setRejectModalOpen] = useState(false);
  const [selectedClaimId, setSelectedClaimId] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [processing, setProcessing] = useState(false);

  // Editable card states
  const [editStates, setEditStates] = useState<Record<string, any>>({});

  useEffect(() => {
    fetchPaymentMethods();
    fetchClaims();
  }, []);

  const fetchPaymentMethods = async () => {
    setLoadingMethods(true);
    try {
      const res = await adminFetch("/api/payments?type=methods");
      const data = await res.json();
      if (res.ok && data.success) {
        setPaymentMethods(data.data || []);
        // Initialize edit states
        const initialStates: Record<string, any> = {};
        (data.data || []).forEach((m: any) => {
          initialStates[m._id] = {
            displayName: m.displayName || "",
            accountNumber: m.accountNumber || "",
            accountName: m.accountName || "",
            instructions: m.instructions || ""
          };
        });
        setEditStates(initialStates);
      } else {
        showAlert("error", data.error || "Failed to load payment methods.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error loading payment methods.");
    } finally {
      setLoadingMethods(false);
    }
  };

  const fetchClaims = async () => {
    setLoadingClaims(true);
    try {
      const res = await adminFetch("/api/payments?type=claims");
      const data = await res.json();
      if (res.ok && data.success) {
        setClaims(data.data || []);
      } else {
        showAlert("error", data.error || "Failed to load payment claims.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error loading payment claims.");
    } finally {
      setLoadingClaims(false);
    }
  };

  const seedDefaultMethods = async () => {
    try {
      const res = await adminFetch("/api/payments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "seedDefaultPaymentMethods" })
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showAlert("success", "Default payment methods seeded successfully.");
        fetchPaymentMethods();
      } else {
        showAlert("error", data.error || "Failed to seed default methods.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error seeding methods.");
    }
  };

  const handleToggleMethod = async (id: string, currentEnabled: boolean) => {
    try {
      const res = await adminFetch("/api/payments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "updatePaymentMethod",
          settingsId: id,
          isEnabled: !currentEnabled,
        }),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setPaymentMethods(methods =>
          methods.map(m => (m._id === id ? { ...m, isEnabled: !currentEnabled } : m))
        );
      } else {
        showAlert("error", data.error || "Failed to toggle payment method.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error toggling payment method.");
    }
  };

  const handleSaveMethod = async (id: string) => {
    try {
      const updates = editStates[id] || {};
      const res = await adminFetch("/api/payments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "updatePaymentMethod",
          settingsId: id,
          ...updates,
        }),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showAlert("success", "Payment method updated successfully.");
        fetchPaymentMethods();
      } else {
        showAlert("error", data.error || "Failed to update payment method.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error updating payment method.");
    }
  };

  const handleApprove = async (claimId: string) => {
    setProcessing(true);
    try {
      const res = await adminFetch("/api/payments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "approvePaymentClaim",
          claimId,
        }),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showAlert("success", "Claim approved and locked successfully.");
        fetchClaims();
      } else {
        showAlert("error", data.error || "Could not approve this claim. An automated (aggregator) payment can be approved only after the provider has confirmed the exact amount; a manual claim must be for the claimant's own order.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error approving claim.");
    } finally {
      setProcessing(false);
    }
  };

  const handleRejectClick = (claimId: string) => {
    setSelectedClaimId(claimId);
    setRejectionReason("");
    setRejectModalOpen(true);
  };

  const confirmReject = async () => {
    if (!rejectionReason.trim()) {
      showAlert("error", "Please provide a rejection reason.");
      return;
    }
    setProcessing(true);
    try {
      const res = await adminFetch("/api/payments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "rejectPaymentClaim",
          claimId: selectedClaimId,
          rejectionReason,
        }),
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showAlert("success", "Claim rejected.");
        setRejectModalOpen(false);
        fetchClaims();
      } else {
        showAlert("error", data.error || "Failed to reject claim.");
      }
    } catch (e) {
      console.error(e);
      showAlert("error", "Error rejecting claim.");
    } finally {
      setProcessing(false);
    }
  };

  const showAlert = (type: "success" | "error", message: string) => {
    setAlert({ type, message });
    setTimeout(() => setAlert(null), 3000);
  };

  const handleEditChange = (id: string, field: string, value: string) => {
    setEditStates(prev => ({
      ...prev,
      [id]: {
        ...prev[id],
        [field]: value
      }
    }));
  };

  const formatCurrency = (amount: number) => {
    return `SLE ${amount.toLocaleString(undefined, { minimumFractionDigits: 2 })}`;
  };

  const formatDate = (ts: number) => {
    const diff = Date.now() - ts;
    const minutes = Math.floor(diff / 60000);
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours} hours ago`;
    return new Date(ts).toLocaleDateString();
  };

  const getBadgeClass = (type: string) => {
    if (type === "AUTO") return styles.badgeAuto;
    if (type === "MANUAL") return styles.badgeManual;
    return styles.badgeBank;
  };

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <h1 className={styles.title}>
          <CreditCard size={28} />
          Payments Control Center
        </h1>
        <p className={styles.subtitle}>
          Manage payment providers and approve escrow claims.
        </p>
      </header>

      {alert && (
        <div className={`${styles.alert} ${alert.type === "success" ? styles.alertSuccess : styles.alertError}`}>
          {alert.type === "success" ? <CheckCircle2 size={20} /> : <AlertCircle size={20} />}
          {alert.message}
        </div>
      )}

      <div className={styles.layout}>
        {/* Section 1: Payment Methods Configurator */}
        <section>
          <h2 className={styles.sectionTitle}>
            <Settings size={20} />
            Payment Methods
          </h2>
          
          {loadingMethods ? (
            <div className={styles.emptyState}>Loading methods...</div>
          ) : paymentMethods.length === 0 ? (
            <div className={styles.emptyState}>
              <Zap size={48} className={styles.emptyStateIcon} />
              <p>No payment methods found.</p>
              <button onClick={seedDefaultMethods} className={styles.seedBtn}>
                Seed Default Methods
              </button>
            </div>
          ) : (
            paymentMethods.map(method => (
              <div key={method._id} className={`${styles.card} ${method.isEnabled ? styles.cardEnabled : ""}`}>
                <div className={styles.cardHeader}>
                  <div className={styles.cardTitle}>
                    {method.displayName}
                    <span className={`${styles.badge} ${getBadgeClass(method.type)}`}>
                      {method.type}
                    </span>
                  </div>
                  <label className={styles.toggle}>
                    <input
                      type="checkbox"
                      checked={method.isEnabled}
                      onChange={() => handleToggleMethod(method._id, method.isEnabled)}
                    />
                    <span className={styles.slider}></span>
                  </label>
                </div>

                <div className={styles.formGroup}>
                  <label>Display Name</label>
                  <input
                    type="text"
                    className={styles.input}
                    value={editStates[method._id]?.displayName || ""}
                    onChange={e => handleEditChange(method._id, "displayName", e.target.value)}
                  />
                </div>
                
                <div className={styles.formGroup}>
                  <label>Account Number (optional)</label>
                  <input
                    type="text"
                    className={styles.input}
                    value={editStates[method._id]?.accountNumber || ""}
                    onChange={e => handleEditChange(method._id, "accountNumber", e.target.value)}
                  />
                </div>
                
                <div className={styles.formGroup}>
                  <label>Account Name (optional)</label>
                  <input
                    type="text"
                    className={styles.input}
                    value={editStates[method._id]?.accountName || ""}
                    onChange={e => handleEditChange(method._id, "accountName", e.target.value)}
                  />
                </div>
                
                <div className={styles.formGroup}>
                  <label>Instructions</label>
                  <textarea
                    className={`${styles.input} ${styles.textarea}`}
                    value={editStates[method._id]?.instructions || ""}
                    onChange={e => handleEditChange(method._id, "instructions", e.target.value)}
                  />
                </div>

                <button onClick={() => handleSaveMethod(method._id)} className={styles.saveBtn}>
                  Save Changes
                </button>
              </div>
            ))
          )}
        </section>

        {/* Section 2: Escrow Approval Queue */}
        <section>
          <h2 className={styles.sectionTitle}>
            <Shield size={20} />
            Escrow Approval Queue
            <button
              onClick={fetchClaims}
              style={{ background: "transparent", border: "none", color: "#94a3b8", cursor: "pointer", marginLeft: "auto" }}
              title="Refresh Queue"
            >
              <RefreshCw size={18} />
            </button>
          </h2>

          <div className={styles.tableContainer}>
            {loadingClaims ? (
              <div className={styles.emptyState}>Loading claims...</div>
            ) : claims.length === 0 ? (
              <div className={styles.emptyState}>
                <CheckCircle2 size={48} className={styles.emptyStateIcon} />
                <p>No pending claims.</p>
              </div>
            ) : (
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th>User</th>
                    <th>Amount</th>
                    <th>Provider</th>
                    <th>Ref / Date</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {claims.map(claim => (
                    <tr key={claim._id}>
                      <td>
                        <div style={{ fontWeight: 500 }}>{claim.userName || "Unknown"}</div>
                        <div style={{ fontSize: "0.75rem", color: "#94a3b8" }}>{claim.userEmail || claim.userPhone || "N/A"}</div>
                      </td>
                      <td style={{ fontWeight: 600, color: "#f8fafc" }}>
                        {formatCurrency(claim.amount)}
                      </td>
                      <td>
                        <div className={`${styles.badge} ${getBadgeClass(claim.paymentType)}`}>
                          {claim.providerId}
                        </div>
                      </td>
                      <td>
                        <div style={{ fontFamily: "monospace", color: "#e2e8f0" }}>{claim.transactionReference || "N/A"}</div>
                        <div style={{ fontSize: "0.75rem", color: "#94a3b8", display: "flex", alignItems: "center", gap: "0.25rem" }}>
                          <Clock size={12} /> {formatDate(claim.createdAt)}
                        </div>
                      </td>
                      <td>
                        <div className={styles.actionGroup}>
                          <button
                            onClick={() => handleApprove(claim._id)}
                            disabled={processing}
                            className={styles.approveBtn}
                          >
                            <CheckCircle2 size={14} /> Approve & Lock
                          </button>
                          <button
                            onClick={() => handleRejectClick(claim._id)}
                            disabled={processing}
                            className={styles.rejectBtn}
                          >
                            <XCircle size={14} /> Reject
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </section>
      </div>

      {/* Reject Modal */}
      {rejectModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <h3 className={styles.modalTitle}>Reject Claim</h3>
            <div className={styles.formGroup}>
              <label>Rejection Reason</label>
              <textarea
                className={`${styles.input} ${styles.textarea}`}
                placeholder="E.g., Transaction ID not found in bank statement."
                value={rejectionReason}
                onChange={e => setRejectionReason(e.target.value)}
              />
            </div>
            <div className={styles.modalActions}>
              <button
                className={styles.cancelBtn}
                onClick={() => setRejectModalOpen(false)}
                disabled={processing}
              >
                Cancel
              </button>
              <button
                className={styles.confirmRejectBtn}
                onClick={confirmReject}
                disabled={processing}
              >
                {processing ? "Rejecting..." : "Confirm Reject"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
