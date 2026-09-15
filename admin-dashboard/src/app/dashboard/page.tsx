"use client";
// src/app/dashboard/page.tsx — Dashboard Overview / Stats
import { useEffect, useState } from "react";
import type { AdminSession } from "@/lib/types";
import styles from "./overview.module.css";

interface Stats {
  pendingVerifications: number;
  totalListings: number;
  totalUsers?: number;
}

export default function DashboardPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [stats, setStats] = useState<Stats>({ pendingVerifications: 0, totalListings: 0, totalUsers: 0 });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const raw = sessionStorage.getItem("adminSession");
    if (raw) setSession(JSON.parse(raw));
  }, []);

  useEffect(() => {
    if (!session) return;
    (async () => {
      try {
        const [vRes, lRes, uRes] = await Promise.all([
          fetch(`/api/verifications?adminId=${session.user.id}&sessionToken=${session.user.sessionToken}&status=pending`),
          fetch("/api/listings"),
          fetch(`/api/users?adminId=${session.user.id}&sessionToken=${session.user.sessionToken}`),
        ]);
        const vData = await vRes.json();
        const lData = await lRes.json();
        const uData = await uRes.json();
        setStats({
          pendingVerifications: vData.success ? (vData.data?.length ?? 0) : 0,
          totalListings: lData.success ? (lData.data?.length ?? 0) : 0,
          totalUsers: uData.success ? (uData.data?.length ?? 0) : 0,
        });
      } catch {}
      setLoading(false);
    })();
  }, [session]);

  const cards = [
    {
      icon: "👥",
      label: "Total App Users",
      value: loading ? "…" : (stats.totalUsers ?? 0).toString(),
      color: "#8b5cf6",
      href: "/dashboard/users",
      cta: "View Directory →",
    },
    {
      icon: "⏳",
      label: "Pending Verifications",
      value: loading ? "…" : stats.pendingVerifications.toString(),
      color: "#f59e0b",
      href: "/dashboard/verifications",
      cta: "Review Queue →",
    },
    {
      icon: "🏘️",
      label: "Total Listings",
      value: loading ? "…" : stats.totalListings.toString(),
      color: "#3b82f6",
      href: "/dashboard/listings",
      cta: "Inspect Listings →",
    },
    {
      icon: "⚡",
      label: "Quick Seed",
      value: "1-click",
      color: "#10b981",
      href: "/dashboard/seed",
      cta: "Open Seeder →",
    },
  ];

  return (
    <div>
      <div className={styles.pageHeader}>
        <div>
          <h1 className={styles.pageTitle}>Admin Overview</h1>
          <p className={styles.pageSubtitle}>
            Vektolux platform management — connected to production Convex backend
          </p>
        </div>
        <div className={styles.liveBadge}>
          <span className={styles.liveDot} />
          Live
        </div>
      </div>

      <div className={styles.statsGrid}>
        {cards.map((card) => (
          <a key={card.label} href={card.href} className={styles.statCard} target={card.href.startsWith("http") ? "_blank" : undefined} rel="noopener noreferrer">
            <div className={styles.statIcon} style={{ background: `${card.color}20`, color: card.color }}>
              {card.icon}
            </div>
            <div className={styles.statValue} style={{ color: card.color }}>{card.value}</div>
            <div className={styles.statLabel}>{card.label}</div>
            <div className={styles.statCta} style={{ color: card.color }}>{card.cta}</div>
          </a>
        ))}
      </div>

      <div className={styles.infoBox}>
        <h3>📋 About this Dashboard</h3>
        <ul>
          <li>Runs locally on <code>localhost:3000</code> — never exposed to the internet</li>
          <li>Connected directly to the live <strong>Convex production</strong> cloud backend</li>
          <li>Real-time: any user verification on the mobile app appears in the queue immediately</li>
          <li>Approve or reject agent/merchant applications with one click</li>
          <li>Seed test data and inspect all platform listings</li>
        </ul>
      </div>
    </div>
  );
}
