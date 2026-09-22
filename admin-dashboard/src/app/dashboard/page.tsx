"use client";
// src/app/dashboard/page.tsx — Live Admin Overview with Analytics, Charts & KYC Demographics
import {
  Users,
  Clock,
  FolderOpen,
  RotateCw,
  ShieldCheck,
  CheckCircle2,
  DollarSign,
} from "lucide-react";
import { useEffect, useState, useMemo } from "react";
import dynamic from "next/dynamic";
import type { AdminSession } from "@/lib/types";
import styles from "./overview.module.css";

const AnalyticsCharts = dynamic(
  () => import("@/components/dashboard/AnalyticsCharts"),
  {
    ssr: false,
    loading: () => (
      <div style={{ padding: "40px 0", textAlign: "center", color: "#64748b" }}>
        Loading real-time financial charts & analytics…
      </div>
    ),
  }
);

interface DailyVolumePoint {
  date: string;
  day: string;
  label: string;
  volume: number;
  transactions: number;
}

interface GenderPoint {
  name: string;
  value: number;
  percentage: number;
  color: string;
}

interface RolePoint {
  name: string;
  group: string;
  value: number;
  percentage: number;
  color: string;
}

interface AnalyticsData {
  financialVolume: {
    currency: string;
    grossVolume: number;
    totalTransactions: number;
    completedCount: number;
    pendingCount: number;
    failedCount: number;
    volumeTimeline: DailyVolumePoint[];
  };
  userDemographics: {
    totalUsers: number;
    activeUsers: number;
    verifiedUsers: number;
    genderDemographics: GenderPoint[];
    roleDistribution: RolePoint[];
    rawRoleCounts: Record<string, number>;
  };
  timestamp: number;
}

export default function DashboardPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [pendingVerifications, setPendingVerifications] = useState(0);
  const [totalListings, setTotalListings] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    setIsMounted(true);
    const raw = sessionStorage.getItem("adminSession");
    if (raw) {
      try {
        setSession(JSON.parse(raw));
      } catch (e) {
        console.error("Failed to parse admin session", e);
      }
    }
  }, []);

  const fetchData = async (isManualRefresh = false) => {
    if (isManualRefresh) setRefreshing(true);
    try {
      const adminId = session?.user?.id || "";
      const sessionToken = session?.user?.sessionToken || "";

      const queryParams = adminId
        ? `?adminId=${encodeURIComponent(adminId)}&sessionToken=${encodeURIComponent(sessionToken)}`
        : "";

      const [analyticsRes, vRes, lRes] = await Promise.all([
        fetch(`/api/analytics${queryParams}`),
        fetch(`/api/verifications${queryParams ? queryParams + "&status=pending" : "?status=pending"}`),
        fetch("/api/listings"),
      ]);

      const analyticsJson = await analyticsRes.json();
      if (analyticsJson.success && analyticsJson.data) {
        setAnalytics(analyticsJson.data);
      }

      const vJson = await vRes.json();
      if (vJson.success) {
        setPendingVerifications(vJson.data?.length ?? 0);
      }

      const lJson = await lRes.json();
      if (lJson.success) {
        setTotalListings(lJson.data?.length ?? 0);
      }
    } catch (err) {
      console.error("Failed to fetch dashboard data:", err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [session]);

  // Derived user statistics
  const totalUsers = analytics?.userDemographics?.totalUsers ?? 0;
  const activeUsers = analytics?.userDemographics?.activeUsers ?? 0;
  const verifiedUsers = analytics?.userDemographics?.verifiedUsers ?? 0;
  const grossVolume = analytics?.financialVolume?.grossVolume ?? 0;
  const completedTxCount = analytics?.financialVolume?.completedCount ?? 0;
  const avgTxSize =
    completedTxCount > 0 ? Math.round(grossVolume / completedTxCount) : 0;

  // Formatting currency
  const formatSLE = (val: number) =>
    `SLE ${Number(val || 0).toLocaleString(undefined, {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })}`;



  return (
    <div>
      {/* Top Header */}
      <div className={styles.pageHeader}>
        <div>
          <h1 className={styles.pageTitle}>Admin Overview & Live Analytics</h1>
          <p className={styles.pageSubtitle}>
            Real-time financial volume, KYC demographics, and live user distribution
          </p>
        </div>
        <div className={styles.headerActions}>
          <button
            className={styles.refreshBtn}
            onClick={() => fetchData(true)}
            disabled={refreshing}
            title="Refresh live database aggregates"
          >
            <RotateCw
              size={14}
              style={{
                animation: refreshing ? "spin 1s linear infinite" : "none",
              }}
            />
            {refreshing ? "Updating..." : "Refresh Live"}
          </button>
          <div className={styles.liveBadge}>
            <span className={styles.liveDot} />
            Live Database
          </div>
        </div>
      </div>

      {/* Top 4 Stat Cards */}
      <div className={styles.statsGrid}>
        <a href="/dashboard/users" className={styles.statCard}>
          <div
            className={styles.statIcon}
            style={{ background: "#eff6ff", color: "#2563eb" }}
          >
            <Users size={22} />
          </div>
          <div className={styles.statValue}>
            {loading ? "…" : totalUsers.toString()}
          </div>
          <div className={styles.statLabel}>Total App Users</div>
          <div className={styles.statCta}>View Directory →</div>
        </a>

        <a href="/dashboard/payments" className={styles.statCard}>
          <div
            className={styles.statIcon}
            style={{ background: "#ecfdf5", color: "#059669" }}
          >
            <DollarSign size={22} />
          </div>
          <div className={styles.statValue} style={{ color: "#059669" }}>
            {loading ? "…" : formatSLE(grossVolume)}
          </div>
          <div className={styles.statLabel}>Gross Volume (SLE)</div>
          <div className={styles.statCta}>Payments & Claims →</div>
        </a>

        <a href="/dashboard/verifications" className={styles.statCard}>
          <div
            className={styles.statIcon}
            style={{ background: "#fffbeb", color: "#d97706" }}
          >
            <Clock size={22} />
          </div>
          <div className={styles.statValue} style={{ color: "#d97706" }}>
            {loading ? "…" : pendingVerifications.toString()}
          </div>
          <div className={styles.statLabel}>Pending Verifications</div>
          <div className={styles.statCta}>Review Queue →</div>
        </a>

        <a href="/dashboard/listings" className={styles.statCard}>
          <div
            className={styles.statIcon}
            style={{ background: "#f5f3ff", color: "#7c3aed" }}
          >
            <FolderOpen size={22} />
          </div>
          <div className={styles.statValue}>
            {loading ? "…" : totalListings.toString()}
          </div>
          <div className={styles.statLabel}>Active Listings</div>
          <div className={styles.statCta}>Inspect Listings →</div>
        </a>
      </div>

      {/* CHARTS SECTION (Client Component via next/dynamic to protect SSR) */}
      <AnalyticsCharts
        analytics={analytics}
        loading={loading}
        formatSLE={formatSLE}
      />

      {/* Database Verification & Info Box */}
      <div className={styles.infoBox}>
        <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <ShieldCheck size={20} color="#10b981" />
          Live Cloud Engine Status
        </h3>
        <ul>
          <li>
            Connected to Convex Cloud deployment{" "}
            <code>ideal-poodle-813.convex.cloud</code>.
          </li>
          <li>
            Zero mock numbers: live database aggregations are derived directly from the{" "}
            <code>users</code> and <code>transactions</code> tables.
          </li>
          <li>
            Gender demographics are mapped dynamically to the KYC{" "}
            <code>gender</code> column (categorized under Male, Female, or Unspecified / Not Disclosed).
          </li>
          <li>
            Financial curves update reactively as transactions are settled through Orange Money, Afrimoney, or Moneroo.
          </li>
        </ul>
      </div>
    </div>
  );
}
