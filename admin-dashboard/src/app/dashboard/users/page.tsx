"use client";
// src/app/dashboard/users/page.tsx — Platform Users Directory & Moderation Console
import {
  RefreshCcw,
  AlertTriangle,
  Users,
  User,
  Car,
  Building,
  Store,
  Shield,
  Mail,
  Phone,
  CheckCircle2,
  Clock,
  CircleDot,
  Activity,
  X,
  Trash2,
  Eye,
  FileText,
  ExternalLink,
  Ban,
  ShieldCheck,
  UserX,
} from "lucide-react";
import { useEffect, useState, useCallback } from "react";
import type { AdminSession, UserRecord } from "@/lib/types";
import styles from "./users.module.css";

interface UserFullDetails {
  user: {
    id: string;
    name: string;
    email: string;
    phone: string;
    role: string;
    kycStatus: string;
    verificationStatus: string;
    verificationBadge: string;
    isActive: boolean;
    bio?: string;
    avatarUrl?: string;
    businessName?: string;
    tinNumber?: string;
    documentUrl?: string;
    rejectionReason?: string;
    createdAt?: number;
    updatedAt?: number;
  };
  properties: Array<{
    id: string;
    title: string;
    category: string;
    price: number;
    city: string;
    isPublished: boolean;
    imageUrls: string[];
    createdAt?: number;
  }>;
  vehicles: Array<{
    id: string;
    make: string;
    model: string;
    year: number;
    vehicleType: string;
    listingIntent: string;
    salePrice?: number;
    pricePerDay?: number;
    isPublished: boolean;
    imageUrls: string[];
    createdAt?: number;
  }>;
}

export default function UsersDirectoryPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [users, setUsers] = useState<UserRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [purging, setPurging] = useState(false);
  const [roleFilter, setRoleFilter] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [actionId, setActionId] = useState<string | null>(null);
  const [error, setError] = useState("");

  // Inspection Modal State
  const [inspectingUserId, setInspectingUserId] = useState<string | null>(null);
  const [inspectingDetails, setInspectingDetails] = useState<UserFullDetails | null>(null);
  const [loadingDetails, setLoadingDetails] = useState(false);
  const [moderatingAction, setModeratingAction] = useState(false);

  useEffect(() => {
    const raw = sessionStorage.getItem("adminSession");
    if (raw) setSession(JSON.parse(raw));
  }, []);

  const loadUsers = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({
        adminId: session.user.id,
        sessionToken: session.user.sessionToken,
        role: roleFilter,
      });
      if (searchQuery.trim()) {
        params.append("q", searchQuery.trim());
      }
      const res = await fetch(`/api/users?${params.toString()}`);
      const data = await res.json();
      if (data.success) {
        setUsers(data.data ?? []);
      } else {
        setError(data.error ?? "Failed to load users.");
      }
    } catch {
      setError("Network error. Could not connect to users API.");
    }
    setLoading(false);
  }, [session, roleFilter, searchQuery]);

  useEffect(() => {
    loadUsers();

    // Periodic 12-second live sync with Convex database
    const interval = setInterval(() => {
      loadUsers();
    }, 12000);

    const onFocus = () => {
      loadUsers();
    };
    window.addEventListener("focus", onFocus);

    return () => {
      clearInterval(interval);
      window.removeEventListener("focus", onFocus);
    };
  }, [loadUsers]);

  // Purge Mock Accounts
  async function handlePurgeMockUsers() {
    if (!session) return;
    if (
      !confirm(
        "Are you sure you want to purge all demo, test, and mock accounts from the live database? This action cannot be undone."
      )
    ) {
      return;
    }

    setPurging(true);
    try {
      const res = await fetch("/api/users/moderate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "purge_mock",
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
        }),
      });
      const data = await res.json();
      if (data.success) {
        alert(data.data?.message ?? "Mock accounts successfully purged.");
        await loadUsers();
      } else {
        alert("Failed to purge mock accounts: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error while purging mock accounts.");
    }
    setPurging(false);
  }

  // Open Inspection Modal
  async function handleInspectUser(userId: string) {
    if (!session) return;
    setInspectingUserId(userId);
    setLoadingDetails(true);
    setInspectingDetails(null);

    try {
      const params = new URLSearchParams({
        adminId: session.user.id,
        sessionToken: session.user.sessionToken,
        userId,
      });
      const res = await fetch(`/api/users/details?${params.toString()}`);
      const data = await res.json();
      if (data.success) {
        setInspectingDetails(data.data);
      } else {
        alert("Failed to load user details: " + (data.error ?? "User not found"));
        setInspectingUserId(null);
      }
    } catch {
      alert("Network error loading user details.");
      setInspectingUserId(null);
    }
    setLoadingDetails(false);
  }

  // Moderation: Verify User
  async function handleVerifyUser(userId: string) {
    if (!session) return;
    if (!confirm("Verify KYC status and grant verified badge to this user?")) return;
    setModeratingAction(true);
    try {
      const res = await fetch("/api/users/moderate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "verify",
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          userId,
        }),
      });
      const data = await res.json();
      if (data.success) {
        alert("User KYC status updated to VERIFIED.");
        await handleInspectUser(userId);
        await loadUsers();
      } else {
        alert("Failed to verify user: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error.");
    }
    setModeratingAction(false);
  }

  // Moderation: Set Status (ACTIVE / SUSPENDED / BANNED)
  async function handleSetStatus(userId: string, newStatus: "ACTIVE" | "SUSPENDED" | "BANNED") {
    if (!session) return;
    const label = newStatus === "ACTIVE" ? "Reactivate" : newStatus === "SUSPENDED" ? "Suspend" : "Ban";
    if (!confirm(`${label} this user account?`)) return;
    setModeratingAction(true);
    try {
      const res = await fetch("/api/users/moderate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "status",
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          userId,
          status: newStatus,
        }),
      });
      const data = await res.json();
      if (data.success) {
        alert(`User account status updated to ${newStatus}.`);
        await handleInspectUser(userId);
        await loadUsers();
      } else {
        alert("Failed to update status: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error.");
    }
    setModeratingAction(false);
  }

  // Moderation: Delete User
  async function handleDeleteUser(userId: string, name: string) {
    if (!session) return;
    if (
      !confirm(
        `PERMANENT ACTION: Are you sure you want to permanently delete user "${name}" and all associated data? This cannot be undone.`
      )
    ) {
      return;
    }
    setModeratingAction(true);
    try {
      const res = await fetch("/api/users/moderate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "delete",
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          userId,
        }),
      });
      const data = await res.json();
      if (data.success) {
        alert("User successfully deleted.");
        setInspectingUserId(null);
        setInspectingDetails(null);
        await loadUsers();
      } else {
        alert("Failed to delete user: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error.");
    }
    setModeratingAction(false);
  }

  // Quick toggle from table row
  async function handleToggleStatus(user: UserRecord, e: React.MouseEvent) {
    e.stopPropagation();
    if (!session) return;
    const newStatus = !user.isActive;
    const confirmMsg = newStatus
      ? `Reactivate account for "${user.name}"?`
      : `Are you sure you want to suspend "${user.name}"?`;
    if (!confirm(confirmMsg)) return;

    setActionId(user.id);
    try {
      const res = await fetch("/api/users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          userId: user.id,
          isActive: newStatus,
        }),
      });
      const data = await res.json();
      if (data.success) {
        setUsers((prev) =>
          prev.map((u) => (u.id === user.id ? { ...u, isActive: newStatus } : u))
        );
      } else {
        alert("Failed to update status: " + (data.error ?? "Unknown error"));
      }
    } catch {
      alert("Network error updating status.");
    }
    setActionId(null);
  }

  function formatDate(ts?: number) {
    if (!ts) return "—";
    return new Date(ts).toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  }

  const roleBadges: Record<
    string,
    { bg: string; color: string; label: string; icon: React.ReactNode }
  > = {
    client: { bg: "rgba(59,130,246,0.12)", color: "#3b82f6", label: "Client", icon: <User size={14} style={{ display: "inline-block" }} /> },
    driver: { bg: "rgba(245,158,11,0.12)", color: "#f59e0b", label: "Driver", icon: <Car size={14} style={{ display: "inline-block" }} /> },
    agent: { bg: "rgba(16,185,129,0.12)", color: "#10b981", label: "Agent", icon: <Building size={14} style={{ display: "inline-block" }} /> },
    merchant: { bg: "rgba(139,92,246,0.12)", color: "#8b5cf6", label: "Merchant", icon: <Store size={14} style={{ display: "inline-block" }} /> },
    admin: { bg: "rgba(236,72,153,0.12)", color: "#ec4899", label: "Admin", icon: <Shield size={14} style={{ display: "inline-block" }} /> },
  };

  return (
    <div>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>All Platform Users</h1>
          <p className={styles.subtitle}>
            Live directory of all registered mobile and web users across Sierra Leone.
          </p>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <button
            onClick={handlePurgeMockUsers}
            className={styles.btnPurge}
            disabled={purging || loading}
            title="Purge mock and demo seed accounts from live Convex database"
          >
            {purging ? "Purging…" : <><Trash2 size={16} /> Purge Mock Accounts</>}
          </button>
          <button
            onClick={loadUsers}
            className={styles.refreshBtn}
            disabled={loading}
            style={{ display: "flex", alignItems: "center", gap: 4 }}
          >
            {loading ? "Loading…" : <><RefreshCcw size={16} /> Refresh Users</>}
          </button>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className={styles.filterBar}>
        <div className={styles.roleTabs}>
          {[
            { id: "all", label: "All Users" },
            { id: "client", label: "Clients" },
            { id: "driver", label: "Drivers" },
            { id: "agent", label: "Agents" },
            { id: "merchant", label: "Merchants" },
            { id: "admin", label: "Admins" },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setRoleFilter(tab.id)}
              className={`${styles.roleTab} ${roleFilter === tab.id ? styles.roleTabActive : ""}`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        <div className={styles.searchBox}>
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search by name, email, phone..."
            className={styles.searchInput}
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery("")}
              className={styles.clearSearchBtn}
              style={{ display: "flex", alignItems: "center", justifyContent: "center" }}
            >
              <X size={14} />
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className={styles.errorBox} style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <AlertTriangle size={16} /> {error}
        </div>
      )}

      {/* Count Indicator */}
      <div className={styles.counterBar}>
        <span>
          Total Users: <strong>{users.length}</strong>
        </span>
        {roleFilter !== "all" && <span className={styles.filterBadge}>Role: {roleFilter}</span>}
      </div>

      {/* Loading */}
      {loading && !error && (
        <div className={styles.loadingBox}>
          <div className={styles.spinner} />
          <span>Fetching platform users…</span>
        </div>
      )}

      {/* Empty */}
      {!loading && !error && users.length === 0 && (
        <div className={styles.emptyBox}>
          <div className={styles.emptyIcon}>
            <Users size={32} />
          </div>
          <div className={styles.emptyText}>No users found matching the selected filters.</div>
        </div>
      )}

      {/* Users Table */}
      {!loading && users.length > 0 && (
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>User</th>
                <th>Role</th>
                <th>Contact</th>
                <th>Verification</th>
                <th>Status</th>
                <th>Joined</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => {
                const roleConfig = roleBadges[u.role] ?? {
                  bg: "rgba(148,163,184,0.12)",
                  color: "#94a3b8",
                  label: u.role,
                  icon: <User size={14} style={{ display: "inline-block" }} />,
                };
                return (
                  <tr
                    key={u.id}
                    onClick={() => handleInspectUser(u.id)}
                    className={u.isActive ? styles.rowActive : styles.rowSuspended}
                    style={{ cursor: "pointer" }}
                    title="Click row to inspect user profile and listings"
                  >
                    {/* User Profile */}
                    <td>
                      <div className={styles.userCell}>
                        {u.avatarUrl ? (
                          <img
                            src={u.avatarUrl}
                            alt={u.name}
                            className={styles.avatarImg}
                            onError={(e) => {
                              const img = e.currentTarget;
                              img.style.display = "none";
                              const fallback = img.nextElementSibling as HTMLElement;
                              if (fallback) fallback.style.display = "flex";
                            }}
                          />
                        ) : null}
                        <div
                          className={styles.avatar}
                          style={{
                            background: `linear-gradient(135deg, ${roleConfig.color}, #0f172a)`,
                            display: u.avatarUrl ? "none" : "flex",
                          }}
                        >
                          {u.name?.charAt(0).toUpperCase() || "?"}
                        </div>
                        <div>
                          <div className={styles.userName}>{u.name}</div>
                          {u.businessName && (
                            <div
                              className={styles.businessName}
                              style={{ display: "flex", alignItems: "center", gap: 4 }}
                            >
                              <Building size={12} /> {u.businessName}
                            </div>
                          )}
                          <div className={styles.userId}>ID: {u.id.substring(0, 8)}…</div>
                        </div>
                      </div>
                    </td>

                    {/* Role */}
                    <td>
                      <span
                        className={styles.roleBadge}
                        style={{
                          background: roleConfig.bg,
                          color: roleConfig.color,
                          border: `1px solid ${roleConfig.color}40`,
                          display: "inline-flex",
                          alignItems: "center",
                          gap: 4,
                        }}
                      >
                        {roleConfig.icon} {roleConfig.label}
                      </span>
                    </td>

                    {/* Contact */}
                    <td>
                      <div className={styles.contactCell}>
                        <div
                          className={styles.emailText}
                          style={{ display: "flex", alignItems: "center", gap: 4 }}
                        >
                          <Mail size={12} /> {u.email}
                        </div>
                        <div
                          className={styles.phoneText}
                          style={{ display: "flex", alignItems: "center", gap: 4 }}
                        >
                          <Phone size={12} /> {u.phone || "No phone"}
                        </div>
                        {u.tinNumber && <div className={styles.tinText}>TIN: {u.tinNumber}</div>}
                      </div>
                    </td>

                    {/* Verification */}
                    <td>
                      <span
                        style={{ display: "inline-flex", alignItems: "center", gap: 4 }}
                        className={`${styles.badge} ${
                          u.isVerified ||
                          u.verificationStatus === "approved" ||
                          u.verificationStatus === "verified"
                            ? styles.badgeVerified
                            : u.verificationStatus === "pending"
                            ? styles.badgePending
                            : styles.badgeUnverified
                        }`}
                      >
                        {u.isVerified ||
                        u.verificationStatus === "approved" ||
                        u.verificationStatus === "verified" ? (
                          <>
                            <CheckCircle2 size={12} /> Verified
                          </>
                        ) : u.verificationStatus === "pending" ? (
                          <>
                            <Clock size={12} /> Pending
                          </>
                        ) : (
                          <>
                            <CircleDot size={12} /> Unverified
                          </>
                        )}
                      </span>
                    </td>

                    {/* Account Status */}
                    <td>
                      <span
                        style={{ display: "inline-flex", alignItems: "center", gap: 4 }}
                        className={`${styles.statusBadge} ${
                          u.isActive ? styles.statusActive : styles.statusSuspended
                        }`}
                      >
                        {u.isActive ? (
                          <>
                            <Activity size={12} /> Active
                          </>
                        ) : (
                          <>
                            <X size={12} /> Suspended
                          </>
                        )}
                      </span>
                    </td>

                    {/* Joined Date */}
                    <td>
                      <span className={styles.dateText}>{formatDate(u.createdAt)}</span>
                    </td>

                    {/* Actions */}
                    <td>
                      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleInspectUser(u.id);
                          }}
                          className={styles.btnInspect}
                          title="Inspect profile, KYC, and listings"
                        >
                          <Eye size={13} /> Inspect
                        </button>
                        <button
                          onClick={(e) => handleToggleStatus(u, e)}
                          disabled={actionId === u.id || u.role === "admin"}
                          className={u.isActive ? styles.btnSuspend : styles.btnActivate}
                          title={u.role === "admin" ? "Admin accounts cannot be suspended" : ""}
                        >
                          {actionId === u.id ? "…" : u.isActive ? "Suspend" : "Activate"}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* User Inspection & Moderation Modal */}
      {inspectingUserId && (
        <div className={styles.modalOverlay} onClick={() => setInspectingUserId(null)}>
          <div className={styles.modalContent} onClick={(e) => e.stopPropagation()}>
            <div className={styles.modalHeader}>
              <div className={styles.modalTitle}>
                <Shield size={20} color="#10b981" /> User Profile & Moderation
              </div>
              <button
                onClick={() => setInspectingUserId(null)}
                className={styles.modalCloseBtn}
              >
                <X size={20} />
              </button>
            </div>

            <div className={styles.modalBody}>
              {loadingDetails ? (
                <div className={styles.loadingBox}>
                  <div className={styles.spinner} />
                  <span>Loading full user profile and assets…</span>
                </div>
              ) : inspectingDetails ? (
                <>
                  {/* Account Overview */}
                  <div className={styles.modalSection}>
                    <div className={styles.modalProfileHeader}>
                      {inspectingDetails.user.avatarUrl ? (
                        <img
                          src={inspectingDetails.user.avatarUrl}
                          alt={inspectingDetails.user.name}
                          className={styles.modalAvatarImg}
                          onError={(e) => {
                            const img = e.currentTarget;
                            img.style.display = "none";
                            const fallback = img.nextElementSibling as HTMLElement;
                            if (fallback) fallback.style.display = "flex";
                          }}
                        />
                      ) : null}
                      <div
                        className={styles.modalAvatarPlaceholder}
                        style={{
                          display: inspectingDetails.user.avatarUrl ? "none" : "flex",
                        }}
                      >
                        {inspectingDetails.user.name?.charAt(0).toUpperCase() || "?"}
                      </div>
                      <div className={styles.modalProfileMeta}>
                        <div className={styles.modalProfileName}>{inspectingDetails.user.name}</div>
                        <div className={styles.modalProfileRole}>
                          <span style={{ textTransform: "capitalize" }}>{inspectingDetails.user.role}</span>
                          {" • "}
                          <span
                            style={{
                              color:
                                inspectingDetails.user.verificationStatus === "verified" ||
                                inspectingDetails.user.kycStatus === "VERIFIED"
                                  ? "#10b981"
                                  : "#f59e0b",
                              fontWeight: 700,
                            }}
                          >
                            {(inspectingDetails.user.verificationStatus || inspectingDetails.user.kycStatus || "UNVERIFIED").toUpperCase()}
                          </span>
                        </div>
                        {inspectingDetails.user.avatarUrl && (
                          <a
                            href={inspectingDetails.user.avatarUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            className={styles.avatarUrlLink}
                            onClick={(e) => e.stopPropagation()}
                          >
                            <ExternalLink size={12} /> View Avatar Image Asset
                          </a>
                        )}
                      </div>
                    </div>

                    <div className={styles.modalSectionTitle} style={{ marginTop: 18 }}>
                      <User size={16} /> Personal Information
                    </div>
                    <div className={styles.infoGrid}>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Full Name</span>
                        <span className={styles.infoValue}>
                          {inspectingDetails.user.name}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Email</span>
                        <span className={styles.infoValue}>
                          {inspectingDetails.user.email}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Phone</span>
                        <span className={styles.infoValue}>
                          {inspectingDetails.user.phone || "None"}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Role</span>
                        <span className={styles.infoValue} style={{ textTransform: "capitalize" }}>
                          {inspectingDetails.user.role}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>KYC Status</span>
                        <span
                          className={styles.infoValue}
                          style={{
                            color:
                              inspectingDetails.user.kycStatus === "VERIFIED"
                                ? "#10b981"
                                : "#f59e0b",
                            fontWeight: 700,
                          }}
                        >
                          {inspectingDetails.user.kycStatus || "PENDING_VERIFICATION"}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Account State</span>
                        <span
                          className={styles.infoValue}
                          style={{
                            color: inspectingDetails.user.isActive ? "#10b981" : "#ef4444",
                            fontWeight: 700,
                          }}
                        >
                          {inspectingDetails.user.isActive ? "ACTIVE" : "SUSPENDED"}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Joined</span>
                        <span className={styles.infoValue}>
                          {formatDate(inspectingDetails.user.createdAt)}
                        </span>
                      </div>
                      <div className={styles.infoItem}>
                        <span className={styles.infoLabel}>Convex User ID</span>
                        <span
                          className={styles.infoValue}
                          style={{ fontFamily: "monospace", fontSize: 11 }}
                        >
                          {inspectingDetails.user.id}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Bio */}
                  <div className={styles.modalSection}>
                    <div className={styles.modalSectionTitle}>
                      <FileText size={16} /> User Bio
                    </div>
                    <div className={styles.bioBox}>
                      {inspectingDetails.user.bio || "No personal bio provided by the user."}
                    </div>
                  </div>

                  {/* Merchant / Business Verification */}
                  {(inspectingDetails.user.businessName ||
                    inspectingDetails.user.tinNumber ||
                    inspectingDetails.user.documentUrl) && (
                    <div className={styles.modalSection}>
                      <div className={styles.modalSectionTitle}>
                        <Store size={16} /> Business & KYC Verification
                      </div>
                      <div className={styles.infoGrid}>
                        {inspectingDetails.user.businessName && (
                          <div className={styles.infoItem}>
                            <span className={styles.infoLabel}>Business Name</span>
                            <span className={styles.infoValue}>
                              {inspectingDetails.user.businessName}
                            </span>
                          </div>
                        )}
                        {inspectingDetails.user.tinNumber && (
                          <div className={styles.infoItem}>
                            <span className={styles.infoLabel}>TIN Number</span>
                            <span className={styles.infoValue}>
                              {inspectingDetails.user.tinNumber}
                            </span>
                          </div>
                        )}
                        {inspectingDetails.user.documentUrl && (
                          <div className={styles.infoItem}>
                            <span className={styles.infoLabel}>KYC Document</span>
                            <a
                              href={inspectingDetails.user.documentUrl}
                              target="_blank"
                              rel="noreferrer"
                              style={{
                                color: "#38bdf8",
                                display: "inline-flex",
                                alignItems: "center",
                                gap: 4,
                                fontSize: 13,
                                textDecoration: "underline",
                              }}
                            >
                              <ExternalLink size={14} /> View Submitted Document
                            </a>
                          </div>
                        )}
                      </div>
                    </div>
                  )}

                  {/* User Real Estate Listings */}
                  <div className={styles.modalSection}>
                    <div className={styles.modalSectionTitle}>
                      <Building size={16} /> Real Estate Listings (
                      {inspectingDetails.properties.length})
                    </div>
                    {inspectingDetails.properties.length === 0 ? (
                      <div style={{ color: "#64748b", fontSize: 13 }}>
                        No property listings created.
                      </div>
                    ) : (
                      <div className={styles.listingList}>
                        {inspectingDetails.properties.map((p) => (
                          <div key={p.id} className={styles.listingItem}>
                            <div>
                              <strong style={{ color: "#f1f5f9" }}>{p.title}</strong>
                              <span style={{ color: "#64748b", marginLeft: 8 }}>
                                {p.city} • {p.category}
                              </span>
                            </div>
                            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                              <span style={{ color: "#10b981", fontWeight: 600 }}>
                                SLE {p.price.toLocaleString()}
                              </span>
                              <span
                                style={{
                                  padding: "2px 6px",
                                  borderRadius: 4,
                                  fontSize: 10,
                                  background: p.isPublished
                                    ? "rgba(16,185,129,0.15)"
                                    : "rgba(148,163,184,0.15)",
                                  color: p.isPublished ? "#10b981" : "#94a3b8",
                                }}
                              >
                                {p.isPublished ? "PUBLISHED" : "DRAFT"}
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>

                  {/* User Vehicle Listings */}
                  <div className={styles.modalSection}>
                    <div className={styles.modalSectionTitle}>
                      <Car size={16} /> Vehicle Listings (
                      {inspectingDetails.vehicles.length})
                    </div>
                    {inspectingDetails.vehicles.length === 0 ? (
                      <div style={{ color: "#64748b", fontSize: 13 }}>
                        No vehicle listings created.
                      </div>
                    ) : (
                      <div className={styles.listingList}>
                        {inspectingDetails.vehicles.map((v) => (
                          <div key={v.id} className={styles.listingItem}>
                            <div>
                              <strong style={{ color: "#f1f5f9" }}>
                                {v.year} {v.make} {v.model}
                              </strong>
                              <span style={{ color: "#64748b", marginLeft: 8 }}>
                                {v.vehicleType} • {v.listingIntent}
                              </span>
                            </div>
                            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                              <span style={{ color: "#10b981", fontWeight: 600 }}>
                                SLE{" "}
                                {(v.salePrice ?? v.pricePerDay ?? 0).toLocaleString()}
                              </span>
                              <span
                                style={{
                                  padding: "2px 6px",
                                  borderRadius: 4,
                                  fontSize: 10,
                                  background: v.isPublished
                                    ? "rgba(16,185,129,0.15)"
                                    : "rgba(148,163,184,0.15)",
                                  color: v.isPublished ? "#10b981" : "#94a3b8",
                                }}
                              >
                                {v.isPublished ? "PUBLISHED" : "DRAFT"}
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </>
              ) : (
                <div style={{ color: "#ef4444" }}>Could not load user details.</div>
              )}
            </div>

            {/* Modal Actions */}
            {inspectingDetails && (
              <div className={styles.modalFooter}>
                <div className={styles.actionGroup}>
                  {/* Verify KYC button */}
                  {inspectingDetails.user.kycStatus !== "VERIFIED" && (
                    <button
                      onClick={() => handleVerifyUser(inspectingDetails.user.id)}
                      disabled={moderatingAction}
                      className={styles.btnVerify}
                    >
                      <ShieldCheck size={16} /> Verify User
                    </button>
                  )}

                  {/* Suspend or Reactivate button */}
                  {inspectingDetails.user.isActive ? (
                    <button
                      onClick={() =>
                        handleSetStatus(inspectingDetails.user.id, "SUSPENDED")
                      }
                      disabled={moderatingAction || inspectingDetails.user.role === "admin"}
                      className={styles.btnBan}
                    >
                      <UserX size={16} /> Suspend Account
                    </button>
                  ) : (
                    <button
                      onClick={() =>
                        handleSetStatus(inspectingDetails.user.id, "ACTIVE")
                      }
                      disabled={moderatingAction}
                      className={styles.btnVerify}
                    >
                      <Activity size={16} /> Reactivate Account
                    </button>
                  )}

                  {/* Ban Account */}
                  <button
                    onClick={() => handleSetStatus(inspectingDetails.user.id, "BANNED")}
                    disabled={moderatingAction || inspectingDetails.user.role === "admin"}
                    className={styles.btnBan}
                  >
                    <Ban size={16} /> Ban Account
                  </button>
                </div>

                <div className={styles.actionGroup}>
                  {/* Permanent Delete */}
                  {inspectingDetails.user.role !== "admin" && (
                    <button
                      onClick={() =>
                        handleDeleteUser(
                          inspectingDetails.user.id,
                          inspectingDetails.user.name
                        )
                      }
                      disabled={moderatingAction}
                      className={styles.btnDelete}
                    >
                      <Trash2 size={16} /> Delete User
                    </button>
                  )}
                  <button
                    onClick={() => setInspectingUserId(null)}
                    className={styles.refreshBtn}
                  >
                    Close
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
