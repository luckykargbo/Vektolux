"use client";
// src/app/dashboard/notifications/page.tsx — Admin Push & In-App Notification Sender
import React, { useState, useEffect } from "react";
import {
  Bell,
  Send,
  Users,
  User,
  Smartphone,
  CheckCircle2,
  AlertCircle,
  Clock,
  ExternalLink,
  Sparkles,
} from "lucide-react";
import styles from "./notifications.module.css";

interface PlatformUser {
  _id: string;
  name: string;
  email: string;
  role: string;
}

interface NotificationLog {
  id: string;
  targetType: string;
  userId?: string;
  title: string;
  body: string;
  deepLinkScreen?: string;
  deepLinkId?: string;
  readCount: number;
  createdAt: number;
}

export default function NotificationsPage() {
  const [targetType, setTargetType] = useState<"all_users" | "single_user">("all_users");
  const [selectedUserId, setSelectedUserId] = useState<string>("");
  const [title, setTitle] = useState<string>("");
  const [message, setMessage] = useState<string>("");
  const [deepLinkScreen, setDeepLinkScreen] = useState<string>("notifications");
  const [deepLinkId, setDeepLinkId] = useState<string>("");

  const [users, setUsers] = useState<PlatformUser[]>([]);
  const [history, setHistory] = useState<NotificationLog[]>([]);
  const [isLoadingUsers, setIsLoadingUsers] = useState<boolean>(true);
  const [isSending, setIsSending] = useState<boolean>(false);
  const [alert, setAlert] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // Load platform users and broadcast history
  useEffect(() => {
    async function loadData() {
      try {
        const rawSession = sessionStorage.getItem("adminSession");
        const session = rawSession ? JSON.parse(rawSession) : null;
        const adminId = session?.user?.id || "admin";

        // Fetch users
        const usersRes = await fetch(`/api/users?adminId=${adminId}`);
        if (usersRes.ok) {
          const uJson = await usersRes.json();
          if (uJson.success && Array.isArray(uJson.data)) {
            setUsers(uJson.data);
            if (uJson.data.length > 0) {
              setSelectedUserId(uJson.data[0]._id);
            }
          }
        }

        // Fetch notification history
        const histRes = await fetch("/api/admin/send-notification");
        if (histRes.ok) {
          const hJson = await histRes.json();
          if (hJson.success && Array.isArray(hJson.data)) {
            setHistory(hJson.data);
          }
        }
      } catch (err) {
        console.error("Failed to load initial notification page data:", err);
      } finally {
        setIsLoadingUsers(false);
      }
    }

    loadData();
  }, []);

  async function handleSendNotification(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim() || !message.trim()) {
      setAlert({ type: "error", text: "Please enter both title and message body." });
      return;
    }

    setIsSending(true);
    setAlert(null);

    try {
      const payload = {
        targetType,
        userId: targetType === "single_user" ? selectedUserId : undefined,
        title: title.trim(),
        message: message.trim(),
        deepLinkScreen: deepLinkScreen || "notifications",
        deepLinkId: deepLinkId.trim() || undefined,
      };

      const res = await fetch("/api/admin/send-notification", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const json = await res.json();

      if (json.success) {
        setAlert({
          type: "success",
          text: `Notification dispatched successfully via ${
            json.data?.pushResult?.mode === "live_fcm" ? "Firebase Cloud Messaging (FCM)" : "Local Cloud Simulation"
          }!`,
        });

        // Reset inputs
        setTitle("");
        setMessage("");
        setDeepLinkId("");

        // Refresh history
        const histRes = await fetch("/api/admin/send-notification");
        if (histRes.ok) {
          const hJson = await histRes.json();
          if (hJson.success && Array.isArray(hJson.data)) {
            setHistory(hJson.data);
          }
        }
      } else {
        setAlert({ type: "error", text: json.error || "Failed to dispatch notification." });
      }
    } catch (err: any) {
      setAlert({ type: "error", text: err?.message || "Failed to send notification." });
    } finally {
      setIsSending(false);
    }
  }

  function applyTemplate(tTitle: string, tBody: string, tScreen: string) {
    setTitle(tTitle);
    setMessage(tBody);
    setDeepLinkScreen(tScreen);
  }

  return (
    <div className={styles.container}>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Push & In-App Notification Center</h1>
          <p className={styles.subtitle}>
            Dispatch heads-up push alerts and in-app announcements to Android, iOS, & Web clients via FCM.
          </p>
        </div>
        <div className={styles.badge}>
          <span className={styles.pulseDot} />
          FCM Gateway Active
        </div>
      </div>

      {alert && (
        <div className={`${styles.alert} ${alert.type === "success" ? styles.alertSuccess : styles.alertError}`}>
          {alert.type === "success" ? <CheckCircle2 size={18} /> : <AlertCircle size={18} />}
          {alert.text}
        </div>
      )}

      {/* Main Grid: Form + Live Device Preview */}
      <div className={styles.grid}>
        {/* Card 1: Notification Composer */}
        <div className={styles.card}>
          <div className={styles.cardHeader}>
            <Send size={18} color="#10b981" />
            <h2 className={styles.cardTitle}>Notification Composer</h2>
          </div>

          <form onSubmit={handleSendNotification}>
            {/* Target Audience Selector */}
            <div className={styles.formGroup}>
              <label className={styles.label}>Recipient Target</label>
              <div className={styles.targetButtons}>
                <button
                  type="button"
                  className={`${styles.targetBtn} ${targetType === "all_users" ? styles.targetBtnActive : ""}`}
                  onClick={() => setTargetType("all_users")}
                >
                  <Users size={16} />
                  Broadcast (All Users)
                </button>
                <button
                  type="button"
                  className={`${styles.targetBtn} ${targetType === "single_user" ? styles.targetBtnActive : ""}`}
                  onClick={() => setTargetType("single_user")}
                >
                  <User size={16} />
                  Specific User
                </button>
              </div>
              <p className={styles.hint}>
                {targetType === "all_users"
                  ? "Subscribes to standard FCM topic 'all_users' for high-throughput broadcast."
                  : "Targeted push alert delivered directly to registered user device tokens."}
              </p>
            </div>

            {/* User Dropdown (if single_user) */}
            {targetType === "single_user" && (
              <div className={styles.formGroup}>
                <label className={styles.label}>Select User</label>
                {isLoadingUsers ? (
                  <p className={styles.hint}>Loading users...</p>
                ) : (
                  <select
                    className={styles.select}
                    value={selectedUserId}
                    onChange={(e) => setSelectedUserId(e.target.value)}
                  >
                    {users.map((u) => (
                      <option key={u._id} value={u._id}>
                        {u.name} ({u.role.toUpperCase()}) — {u.email}
                      </option>
                    ))}
                  </select>
                )}
              </div>
            )}

            {/* Quick Templates */}
            <div className={styles.formGroup}>
              <label className={styles.label}>
                <Sparkles size={12} style={{ display: "inline", marginRight: 4 }} />
                Quick Templates
              </label>
              <div className={styles.quickTemplates}>
                <button
                  type="button"
                  className={styles.templateChip}
                  onClick={() =>
                    applyTemplate(
                      "🎉 Special Weekend Marketplace Deal",
                      "Exclusive discounts on verified beachfront properties and luxury vehicle rentals across Freetown!",
                      "real_estate"
                    )
                  }
                >
                  Marketplace Deal
                </button>
                <button
                  type="button"
                  className={styles.templateChip}
                  onClick={() =>
                    applyTemplate(
                      "🛡️ Escrow Milestone Update",
                      "Your milestone payment tranche has been verified and deposited into secure platform custody.",
                      "escrow_real_estate"
                    )
                  }
                >
                  Escrow Alert
                </button>
                <button
                  type="button"
                  className={styles.templateChip}
                  onClick={() =>
                    applyTemplate(
                      "⚡ System Security & Policy Update",
                      "Please review our updated partner verification requirements and safe deposit release policies.",
                      "notifications"
                    )
                  }
                >
                  Policy Announcement
                </button>
              </div>
            </div>

            {/* Notification Title */}
            <div className={styles.formGroup}>
              <label className={styles.label}>Title</label>
              <input
                type="text"
                className={styles.input}
                placeholder="e.g. Escrow Deposit Confirmed"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                maxLength={80}
                required
              />
            </div>

            {/* Notification Body */}
            <div className={styles.formGroup}>
              <label className={styles.label}>Message Body</label>
              <textarea
                className={styles.textarea}
                placeholder="Write your push notification message here..."
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                maxLength={240}
                required
              />
              <p className={styles.hint}>{message.length} / 240 characters</p>
            </div>

            {/* Deep-Link Routing */}
            <div className={styles.formGroup}>
              <label className={styles.label}>Deep-Link Screen Target</label>
              <select
                className={styles.select}
                value={deepLinkScreen}
                onChange={(e) => setDeepLinkScreen(e.target.value)}
              >
                <option value="notifications">In-App Notification Center</option>
                <option value="home">Home Super App</option>
                <option value="real_estate">Real Estate Marketplace</option>
                <option value="mobility">Auto Marketplace & Rides</option>
                <option value="escrow_real_estate">Property Escrow Contract</option>
                <option value="escrow_vehicle">Vehicle Escrow Contract</option>
                <option value="profile">User Profile & Account</option>
              </select>
            </div>

            <div className={styles.formGroup}>
              <label className={styles.label}>Entity / Contract ID (Optional)</label>
              <input
                type="text"
                className={styles.input}
                placeholder="e.g. j578v1p0w4d0c9f1..."
                value={deepLinkId}
                onChange={(e) => setDeepLinkId(e.target.value)}
              />
            </div>

            <button type="submit" className={styles.submitBtn} disabled={isSending}>
              <Send size={16} />
              {isSending ? "Dispatching Push Alert..." : "Dispatch Push Alert"}
            </button>
          </form>
        </div>

        {/* Card 2: Live Device Mockup Preview */}
        <div className={styles.card}>
          <div className={styles.cardHeader}>
            <Smartphone size={18} color="#10b981" />
            <h2 className={styles.cardTitle}>Live Heads-Up Mobile Preview</h2>
          </div>

          <div className={styles.previewWrap}>
            <div className={styles.phoneFrame}>
              <div className={styles.phoneNotch} />

              {/* Heads-up notification push banner */}
              <div className={styles.pushBanner}>
                <div className={styles.bannerTop}>
                  <div className={styles.bannerApp}>
                    <div className={styles.bannerAppIcon}>V</div>
                    <span className={styles.bannerAppName}>VEKTOLUX</span>
                  </div>
                  <span className={styles.bannerTime}>now</span>
                </div>

                <div className={styles.bannerTitle}>
                  {title.trim() || "Notification Title Preview"}
                </div>
                <div className={styles.bannerBody}>
                  {message.trim() || "Your message body will appear here on user lock screens and heads-up popups..."}
                </div>

                <div className={styles.bannerAction}>
                  Tap to view → {deepLinkScreen}
                </div>
              </div>
            </div>
            <p className={styles.hint} style={{ marginTop: 14, textAlign: "center" }}>
              Android 13+ High-Priority Channel & iOS APNs Alert Preview
            </p>
          </div>
        </div>
      </div>

      {/* Card 3: Dispatch & Broadcast History */}
      <div className={styles.tableCard}>
        <div className={styles.cardHeader}>
          <Clock size={18} color="#10b981" />
          <h2 className={styles.cardTitle}>Recent Notification Logs & Delivery History</h2>
        </div>

        {history.length === 0 ? (
          <p className={styles.hint} style={{ padding: "20px 0", textAlign: "center" }}>
            No notification dispatch history yet. Send your first broadcast above!
          </p>
        ) : (
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Target</th>
                <th className={styles.th}>Title & Message</th>
                <th className={styles.th}>Deep Link</th>
                <th className={styles.th}>Read Count</th>
                <th className={styles.th}>Dispatched</th>
              </tr>
            </thead>
            <tbody>
              {history.map((h) => (
                <tr key={h.id}>
                  <td className={styles.td}>
                    {h.targetType === "all_users" ? (
                      <span className={`${styles.targetTag} ${styles.targetBroadcast}`}>
                        <Users size={12} /> Broadcast
                      </span>
                    ) : (
                      <span className={`${styles.targetTag} ${styles.targetUser}`}>
                        <User size={12} /> Direct User
                      </span>
                    )}
                  </td>
                  <td className={styles.td}>
                    <div style={{ fontWeight: 700, color: "#f8fafc", marginBottom: 2 }}>
                      {h.title}
                    </div>
                    <div style={{ fontSize: 12, color: "#94a3b8" }}>{h.body}</div>
                  </td>
                  <td className={styles.td}>
                    <span style={{ fontSize: 12, color: "#10b981", fontWeight: 600 }}>
                      /{h.deepLinkScreen || "notifications"}
                    </span>
                  </td>
                  <td className={styles.td}>
                    <span style={{ fontWeight: 700, color: "#cbd5e1" }}>{h.readCount} read</span>
                  </td>
                  <td className={styles.td} style={{ fontSize: 12, color: "#64748b" }}>
                    {new Date(h.createdAt).toLocaleString()}
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
