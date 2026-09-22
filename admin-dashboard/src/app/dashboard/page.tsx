"use client";
// src/app/dashboard/page.tsx — Live Admin Overview with Analytics, Charts & KYC Demographics
import {
  Users,
  Clock,
  FolderOpen,
  TrendingUp,
  RotateCw,
  PieChart as PieChartIcon,
  BarChart3,
  ShieldCheck,
  CheckCircle2,
  DollarSign,
} from "lucide-react";
import { useEffect, useState, useMemo } from "react";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  PieChart,
  Pie,
  Cell,
} from "recharts";
import type { AdminSession } from "@/lib/types";
import styles from "./overview.module.css";

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
  const [chartView, setChartView] = useState<"curve" | "bar">("curve");
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

  // Custom Recharts Tooltips
  const CustomVolumeTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload as DailyVolumePoint;
      return (
        <div className={styles.customTooltip}>
          <div className={styles.tooltipTitle}>
            {data.day}, {data.label}
          </div>
          <div className={styles.tooltipValue}>
            {formatSLE(data.volume)}
          </div>
          <div style={{ fontSize: "11.5px", color: "#64748b", marginTop: 2 }}>
            {data.transactions} {data.transactions === 1 ? "transaction" : "transactions"}
          </div>
        </div>
      );
    }
    return null;
  };

  const CustomPieTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0];
      return (
        <div className={styles.customTooltip}>
          <div className={styles.tooltipTitle}>{data.name}</div>
          <div className={styles.tooltipValue} style={{ color: data.payload.color }}>
            {data.value} {data.value === 1 ? "User" : "Users"} ({data.payload.percentage}%)
          </div>
        </div>
      );
    }
    return null;
  };

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

      {/* CHARTS SECTION */}
      <div className={styles.chartsSection}>
        {/* 1. FINANCIAL VOLUME CHART */}
        <div className={styles.chartCard}>
          <div className={styles.chartHeader}>
            <div className={styles.chartTitleWrap}>
              <h2 className={styles.chartTitle}>
                <TrendingUp size={18} color="#10b981" />
                Financial Transaction Volume (SLE)
              </h2>
              <p className={styles.chartSubtitle}>
                Daily settlement volume across Orange Money, Afrimoney, Cards, and P2P transfers
              </p>
            </div>
            <div className={styles.chartControls}>
              <button
                className={`${styles.viewToggleBtn} ${
                  chartView === "curve" ? styles.viewToggleBtnActive : ""
                }`}
                onClick={() => setChartView("curve")}
              >
                Volume Curve
              </button>
              <button
                className={`${styles.viewToggleBtn} ${
                  chartView === "bar" ? styles.viewToggleBtnActive : ""
                }`}
                onClick={() => setChartView("bar")}
              >
                Daily Bars
              </button>
            </div>
          </div>

          <div className={styles.chartSummaryRow}>
            <div className={styles.chartMetric}>
              <span className={styles.metricLabel}>Total Settled</span>
              <span className={styles.metricValue}>{formatSLE(grossVolume)}</span>
            </div>
            <div className={styles.chartMetric}>
              <span className={styles.metricLabel}>Completed Txns</span>
              <span className={styles.metricValue}>{completedTxCount}</span>
            </div>
            <div className={styles.chartMetric}>
              <span className={styles.metricLabel}>Average Txn Size</span>
              <span className={styles.metricValue}>{formatSLE(avgTxSize)}</span>
            </div>
            <div className={styles.chartMetric}>
              <span className={styles.metricLabel}>Pending Txns</span>
              <span className={styles.metricValue} style={{ color: "#d97706" }}>
                {analytics?.financialVolume?.pendingCount ?? 0}
              </span>
            </div>
          </div>

          <div style={{ width: "100%", height: 280 }}>
            {isMounted && (
              <ResponsiveContainer width="100%" height="100%">
                {chartView === "curve" ? (
                  <AreaChart
                    data={analytics?.financialVolume?.volumeTimeline ?? []}
                    margin={{ top: 10, right: 10, left: 0, bottom: 0 }}
                  >
                    <defs>
                      <linearGradient id="colorVolume" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#10b981" stopOpacity={0.25} />
                        <stop offset="95%" stopColor="#10b981" stopOpacity={0.0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
                    <XAxis
                      dataKey="label"
                      tick={{ fill: "#64748b", fontSize: 12 }}
                      stroke="#e2e8f0"
                      tickLine={false}
                    />
                    <YAxis
                      tick={{ fill: "#64748b", fontSize: 12 }}
                      stroke="#e2e8f0"
                      tickLine={false}
                      tickFormatter={(v) => (v >= 1000 ? `${(v / 1000).toFixed(0)}k` : `${v}`)}
                    />
                    <Tooltip content={<CustomVolumeTooltip />} />
                    <Area
                      type="monotone"
                      dataKey="volume"
                      stroke="#10b981"
                      strokeWidth={2.5}
                      fillOpacity={1}
                      fill="url(#colorVolume)"
                    />
                  </AreaChart>
                ) : (
                  <BarChart
                    data={analytics?.financialVolume?.volumeTimeline ?? []}
                    margin={{ top: 10, right: 10, left: 0, bottom: 0 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
                    <XAxis
                      dataKey="label"
                      tick={{ fill: "#64748b", fontSize: 12 }}
                      stroke="#e2e8f0"
                      tickLine={false}
                    />
                    <YAxis
                      tick={{ fill: "#64748b", fontSize: 12 }}
                      stroke="#e2e8f0"
                      tickLine={false}
                      tickFormatter={(v) => (v >= 1000 ? `${(v / 1000).toFixed(0)}k` : `${v}`)}
                    />
                    <Tooltip content={<CustomVolumeTooltip />} />
                    <Bar
                      dataKey="volume"
                      fill="#10b981"
                      radius={[4, 4, 0, 0]}
                    />
                  </BarChart>
                )}
              </ResponsiveContainer>
            )}
          </div>
        </div>

        {/* 2. DEMOGRAPHICS GRID (2 COLUMNS) */}
        <div className={styles.demographicsGrid}>
          {/* GENDER DEMOGRAPHICS */}
          <div className={styles.chartCard}>
            <div className={styles.chartHeader}>
              <div className={styles.chartTitleWrap}>
                <h2 className={styles.chartTitle}>
                  <PieChartIcon size={18} color="#3b82f6" />
                  Gender Demographics (KYC)
                </h2>
                <p className={styles.chartSubtitle}>
                  User distribution based on identity verification records
                </p>
              </div>
            </div>

            <div style={{ width: "100%", height: 220, position: "relative" }}>
              {isMounted && (
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Tooltip content={<CustomPieTooltip />} />
                    <Pie
                      data={analytics?.userDemographics?.genderDemographics ?? []}
                      cx="50%"
                      cy="50%"
                      innerRadius={55}
                      outerRadius={85}
                      paddingAngle={4}
                      dataKey="value"
                    >
                      {(analytics?.userDemographics?.genderDemographics ?? []).map(
                        (entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        )
                      )}
                    </Pie>
                  </PieChart>
                </ResponsiveContainer>
              )}
            </div>

            <div className={styles.demographicsLegend}>
              {(analytics?.userDemographics?.genderDemographics ?? []).map(
                (item) => (
                  <div key={item.name} className={styles.legendItem}>
                    <div className={styles.legendLeft}>
                      <span
                        className={styles.legendColorDot}
                        style={{ background: item.color }}
                      />
                      <span className={styles.legendLabel}>{item.name}</span>
                    </div>
                    <div className={styles.legendRight}>
                      <span className={styles.legendCount}>
                        {item.value} {item.value === 1 ? "user" : "users"}
                      </span>
                      <span className={styles.legendPercent}>
                        {item.percentage}%
                      </span>
                    </div>
                  </div>
                )
              )}
            </div>
          </div>

          {/* ROLE DISTRIBUTION */}
          <div className={styles.chartCard}>
            <div className={styles.chartHeader}>
              <div className={styles.chartTitleWrap}>
                <h2 className={styles.chartTitle}>
                  <BarChart3 size={18} color="#6366f1" />
                  Platform Role Distribution
                </h2>
                <p className={styles.chartSubtitle}>
                  Breakdown across buyers, dealers, transport operators, and administrators
                </p>
              </div>
            </div>

            <div style={{ width: "100%", height: 220 }}>
              {isMounted && (
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart
                    layout="vertical"
                    data={analytics?.userDemographics?.roleDistribution ?? []}
                    margin={{ top: 10, right: 30, left: 20, bottom: 5 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" horizontal={false} />
                    <XAxis
                      type="number"
                      tick={{ fill: "#64748b", fontSize: 11 }}
                      stroke="#e2e8f0"
                      tickLine={false}
                      allowDecimals={false}
                    />
                    <YAxis
                      type="category"
                      dataKey="name"
                      tick={{ fill: "#334155", fontSize: 12, fontWeight: 600 }}
                      stroke="#e2e8f0"
                      tickLine={false}
                      width={120}
                    />
                    <Tooltip
                      formatter={(val: any, name: any, item: any) => [
                        `${val} Users (${item?.payload?.percentage || 0}%)`,
                        item?.payload?.name,
                      ]}
                      contentStyle={{
                        background: "#ffffff",
                        border: "1px solid #e2e8f0",
                        borderRadius: "8px",
                        fontSize: "12.5px",
                        boxShadow: "0 4px 12px rgba(0,0,0,0.08)",
                      }}
                    />
                    <Bar dataKey="value" radius={[0, 6, 6, 0]}>
                      {(analytics?.userDemographics?.roleDistribution ?? []).map(
                        (entry, index) => (
                          <Cell key={`role-cell-${index}`} fill={entry.color} />
                        )
                      )}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              )}
            </div>

            <div className={styles.demographicsLegend}>
              {(analytics?.userDemographics?.roleDistribution ?? []).map((item) => (
                <div key={item.name} className={styles.legendItem}>
                  <div className={styles.legendLeft}>
                    <span
                      className={styles.legendColorDot}
                      style={{ background: item.color }}
                    />
                    <span className={styles.legendLabel}>{item.name}</span>
                  </div>
                  <div className={styles.legendRight}>
                    <span className={styles.legendCount}>
                      {item.value} {item.value === 1 ? "user" : "users"}
                    </span>
                    <span className={styles.legendPercent}>
                      {item.percentage}%
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

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
