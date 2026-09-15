"use client";
// src/app/dashboard/users/page.tsx — Platform Users Directory
import { useEffect, useState, useCallback } from "react";
import type { AdminSession, UserRecord } from "@/lib/types";
import styles from "./users.module.css";

export default function UsersDirectoryPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [users, setUsers] = useState<UserRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [roleFilter, setRoleFilter] = useState("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [actionId, setActionId] = useState<string | null>(null);
  const [error, setError] = useState("");

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
  }, [loadUsers]);

  async function handleToggleStatus(user: UserRecord) {
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

  const roleBadges: Record<string, { bg: string; color: string; label: string; icon: string }> = {
    client: { bg: "rgba(59,130,246,0.12)", color: "#3b82f6", label: "Client", icon: "👤" },
    driver: { bg: "rgba(245,158,11,0.12)", color: "#f59e0b", label: "Driver", icon: "🚗" },
    agent: { bg: "rgba(16,185,129,0.12)", color: "#10b981", label: "Agent", icon: "🏢" },
    merchant: { bg: "rgba(139,92,246,0.12)", color: "#8b5cf6", label: "Merchant", icon: "🏪" },
    admin: { bg: "rgba(236,72,153,0.12)", color: "#ec4899", label: "Admin", icon: "👑" },
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
        <button onClick={loadUsers} className={styles.refreshBtn} disabled={loading}>
          {loading ? "Loading…" : "↻ Refresh Users"}
        </button>
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
            <button onClick={() => setSearchQuery("")} className={styles.clearSearchBtn}>
              ✕
            </button>
          )}
        </div>
      </div>

      {error && <div className={styles.errorBox}>⚠️ {error}</div>}

      {/* Count Indicator */}
      <div className={styles.counterBar}>
        <span>Total Users: <strong>{users.length}</strong></span>
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
          <div className={styles.emptyIcon}>👥</div>
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
                  icon: "👤",
                };
                return (
                  <tr key={u.id} className={u.isActive ? styles.rowActive : styles.rowSuspended}>
                    {/* User Profile */}
                    <td>
                      <div className={styles.userCell}>
                        <div
                          className={styles.avatar}
                          style={{
                            background: `linear-gradient(135deg, ${roleConfig.color}, #0f172a)`,
                          }}
                        >
                          {u.name?.charAt(0).toUpperCase() || "?"}
                        </div>
                        <div>
                          <div className={styles.userName}>{u.name}</div>
                          {u.businessName && (
                            <div className={styles.businessName}>🏢 {u.businessName}</div>
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
                        }}
                      >
                        {roleConfig.icon} {roleConfig.label}
                      </span>
                    </td>

                    {/* Contact */}
                    <td>
                      <div className={styles.contactCell}>
                        <div className={styles.emailText}>📧 {u.email}</div>
                        <div className={styles.phoneText}>📱 {u.phone || "No phone"}</div>
                        {u.tinNumber && (
                          <div className={styles.tinText}>TIN: {u.tinNumber}</div>
                        )}
                      </div>
                    </td>

                    {/* Verification */}
                    <td>
                      <span
                        className={`${styles.badge} ${
                          u.isVerified || u.verificationStatus === "approved" || u.verificationStatus === "verified"
                            ? styles.badgeVerified
                            : u.verificationStatus === "pending"
                            ? styles.badgePending
                            : styles.badgeUnverified
                        }`}
                      >
                        {u.isVerified || u.verificationStatus === "approved" || u.verificationStatus === "verified"
                          ? "✅ Verified"
                          : u.verificationStatus === "pending"
                          ? "⏳ Pending"
                          : "⚪ Unverified"}
                      </span>
                    </td>

                    {/* Account Status */}
                    <td>
                      <span
                        className={`${styles.statusBadge} ${
                          u.isActive ? styles.statusActive : styles.statusSuspended
                        }`}
                      >
                        {u.isActive ? "● Active" : "✕ Suspended"}
                      </span>
                    </td>

                    {/* Joined Date */}
                    <td>
                      <span className={styles.dateText}>{formatDate(u.createdAt)}</span>
                    </td>

                    {/* Actions */}
                    <td>
                      <button
                        onClick={() => handleToggleStatus(u)}
                        disabled={actionId === u.id || u.role === "admin"}
                        className={u.isActive ? styles.btnSuspend : styles.btnActivate}
                        title={u.role === "admin" ? "Admin accounts cannot be suspended" : ""}
                      >
                        {actionId === u.id
                          ? "…"
                          : u.isActive
                          ? "Suspend"
                          : "Activate"}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
