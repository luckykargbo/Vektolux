"use client";
// src/components/dashboard/AnalyticsCharts.tsx
// Pure client-side chart component isolated from SSR to prevent vendor-chunk webpack mismatches

import React, { useState } from "react";
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
import { TrendingUp, PieChart as PieChartIcon, BarChart3 } from "lucide-react";
import styles from "@/app/dashboard/overview.module.css";

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
  count: number;
  percentage: number;
}

interface AnalyticsData {
  summary: {
    totalUsers: number;
    activeUsers: number;
    totalListings: number;
    publishedListings: number;
    totalProperties: number;
    totalVehicles: number;
    pendingVerifications: number;
    activeEscrowHolds: number;
    unreadNotifications: number;
  };
  financialVolume: {
    grossVolumeSLE: number;
    completedCount: number;
    pendingCount: number;
    failedCount: number;
    avgTransactionSize: number;
    volumeTimeline: DailyVolumePoint[];
  };
  userDemographics: {
    genderDemographics: GenderPoint[];
    roleDistribution: RolePoint[];
  };
}

interface Props {
  analytics: AnalyticsData | null;
  loading: boolean;
  formatSLE: (amount: number) => string;
}

export default function AnalyticsCharts({ analytics, loading, formatSLE }: Props) {
  const [chartView, setChartView] = useState<"curve" | "bar">("curve");

  const grossVolume = analytics?.financialVolume?.grossVolumeSLE ?? 0;
  const completedTxCount = analytics?.financialVolume?.completedCount ?? 0;
  const avgTxSize = analytics?.financialVolume?.avgTransactionSize ?? 0;

  // Custom tooltips
  const CustomVolumeTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload as DailyVolumePoint;
      return (
        <div className={styles.customTooltip}>
          <div className={styles.tooltipTitle}>{data.label}</div>
          <div className={styles.tooltipItem}>
            <span className={styles.tooltipLabel}>Settled Volume:</span>
            <span className={styles.tooltipValue}>{formatSLE(data.volume)}</span>
          </div>
          <div className={styles.tooltipItem}>
            <span className={styles.tooltipLabel}>Transactions:</span>
            <span className={styles.tooltipValue}>{data.transactions}</span>
          </div>
        </div>
      );
    }
    return null;
  };

  const CustomPieTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload as GenderPoint;
      return (
        <div className={styles.customTooltip}>
          <div className={styles.tooltipTitle}>{data.name}</div>
          <div className={styles.tooltipItem}>
            <span className={styles.tooltipLabel}>Total Users:</span>
            <span className={styles.tooltipValue}>{data.value}</span>
          </div>
          <div className={styles.tooltipItem}>
            <span className={styles.tooltipLabel}>Share:</span>
            <span className={styles.tooltipValue}>{data.percentage}%</span>
          </div>
        </div>
      );
    }
    return null;
  };

  return (
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
                    boxShadow: "0 4px 6px -1px rgb(0 0 0 / 0.08)",
                  }}
                />
                <Bar
                  dataKey="count"
                  fill="#6366f1"
                  radius={[0, 4, 4, 0]}
                />
              </BarChart>
            </ResponsiveContainer>
          </div>

          <div className={styles.demographicsLegend}>
            {(analytics?.userDemographics?.roleDistribution ?? []).map(
              (role) => (
                <div key={role.name} className={styles.legendItem}>
                  <div className={styles.legendLeft}>
                    <span
                      className={styles.legendColorDot}
                      style={{ background: "#6366f1" }}
                    />
                    <span className={styles.legendLabel}>{role.name}</span>
                  </div>
                  <div className={styles.legendRight}>
                    <span className={styles.legendCount}>
                      {role.count} {role.count === 1 ? "user" : "users"}
                    </span>
                    <span className={styles.legendPercent}>
                      {role.percentage}%
                    </span>
                  </div>
                </div>
              )
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
