"use client";
// src/app/dashboard/seed/page.tsx — Quick Seed Tool
import { useState } from "react";
import styles from "./seed.module.css";

interface SeedTask {
  label: string;
  vertical: "property" | "vehicle" | "both";
  city: string;
  subtitle: string;
  icon: string;
}

const SEED_TASKS: SeedTask[] = [
  { label: "Freetown Real Estate (3 Properties)", subtitle: "Spur Loop Executive Villa, Lumley Ocean Suite & Regent Mountain Ridge", icon: "🏢", vertical: "property", city: "Freetown" },
  { label: "Bo Town Real Estate (2 Properties)", subtitle: "Bo-Tajama Highway Residency & Commercial Gated Compound", icon: "🏡", vertical: "property", city: "Bo" },
  { label: "Freetown Vehicles (3 Vehicles)", subtitle: "Toyota Land Cruiser Prado, TVS King Keke & Hyundai Santa Fe", icon: "🚗", vertical: "vehicle", city: "Freetown" },
  { label: "Makeni & Waterloo Hub (Mixed)", subtitle: "Toyota Hilux 4x4, TVS Star Okada & Waterloo Gated Compound", icon: "🚛", vertical: "both", city: "Makeni" },
];

export default function SeedPage() {
  const [isPublished, setIsPublished] = useState(false);
  const [runningTask, setRunningTask] = useState<string | null>(null);
  const [results, setResults] = useState<{ label: string; message: string; ok: boolean }[]>([]);

  async function runSeed(task: SeedTask) {
    setRunningTask(task.label);
    try {
      const res = await fetch("/api/seed", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ vertical: task.vertical, city: task.city, isPublished }),
      });
      const data = await res.json();
      setResults(prev => [
        { label: task.label, message: data.success ? (data.data?.message ?? "Seeded successfully!") : (data.error ?? "Failed"), ok: data.success },
        ...prev,
      ]);
    } catch (e: any) {
      setResults(prev => [{ label: task.label, message: e.message ?? "Network error", ok: false }, ...prev]);
    }
    setRunningTask(null);
  }

  return (
    <div>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Quick Seed</h1>
          <p className={styles.subtitle}>1-click test data injection across Sierra Leone hubs.</p>
        </div>
      </div>

      {/* Visibility Toggle */}
      <div className={styles.toggleCard}>
        <div>
          <div className={styles.toggleLabel}>Seed Visibility</div>
          <div className={styles.toggleDesc} style={{ color: isPublished ? "#10b981" : "#f59e0b" }}>
            {isPublished
              ? "Listings will be PUBLIC — visible immediately in discovery"
              : "Listings will be PRIVATE DRAFTS — hidden from public discovery"}
          </div>
        </div>
        <button
          onClick={() => setIsPublished(v => !v)}
          className={`${styles.toggle} ${isPublished ? styles.toggleOn : styles.toggleOff}`}
        >
          {isPublished ? "PUBLIC" : "DRAFT"}
        </button>
      </div>

      {/* Seed Buttons */}
      <div className={styles.seedGrid}>
        {SEED_TASKS.map(task => (
          <button
            key={task.label}
            onClick={() => runSeed(task)}
            disabled={runningTask !== null}
            className={styles.seedCard}
          >
            <div className={styles.seedIcon}>{task.icon}</div>
            <div className={styles.seedLabel}>{task.label}</div>
            <div className={styles.seedSubtitle}>{task.subtitle}</div>
            <div className={styles.seedBadge} style={{ background: isPublished ? "#10b981" : "#f59e0b" }}>
              {isPublished ? "PUBLIC" : "PRIVATE DRAFT"}
            </div>
            {runningTask === task.label && (
              <div className={styles.seedLoading}>Seeding…</div>
            )}
          </button>
        ))}
      </div>

      {/* Results Log */}
      {results.length > 0 && (
        <div className={styles.resultsSection}>
          <div className={styles.resultsHeader}>
            <div className={styles.resultsTitle}>Seed Log</div>
            <button onClick={() => setResults([])} className={styles.clearLogBtn}>Clear</button>
          </div>
          <div className={styles.resultsList}>
            {results.map((r, i) => (
              <div key={i} className={`${styles.resultItem} ${r.ok ? styles.resultOk : styles.resultErr}`}>
                <span>{r.ok ? "✅" : "❌"}</span>
                <div>
                  <div className={styles.resultLabel}>{r.label}</div>
                  <div className={styles.resultMsg}>{r.message}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
