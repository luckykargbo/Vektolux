"use client";
// src/app/dashboard/listings/page.tsx — Listings Inspector
import { useEffect, useState, useCallback } from "react";
import type { AdminSession } from "@/lib/types";
import styles from "./listings.module.css";

interface Listing {
  id: string;
  type: string;
  title: string;
  price: number;
  city: string;
  isPublished: boolean;
  ownerName?: string;
  imageUrls?: string[];
  createdAt?: number;
}

export default function ListingsPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [listings, setListings] = useState<Listing[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");
  const [clearing, setClearing] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const raw = sessionStorage.getItem("adminSession");
    if (raw) setSession(JSON.parse(raw));
  }, []);

  const loadListings = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await fetch(`/api/listings?vertical=${filter}`);
      const data = await res.json();
      if (data.success) setListings(data.data ?? []);
      else setError(data.error ?? "Failed to load.");
    } catch { setError("Network error."); }
    setLoading(false);
  }, [filter]);

  useEffect(() => { loadListings(); }, [loadListings]);

  async function handleClearAll() {
    if (!confirm("⚠️ This will permanently delete ALL properties and vehicles from the database. Are you absolutely sure?")) return;
    setClearing(true);
    try {
      const res = await fetch("/api/listings", { method: "DELETE" });
      const data = await res.json();
      if (data.success) { setListings([]); alert("✅ All listings cleared!"); }
      else alert("Failed: " + (data.error ?? "Unknown error"));
    } catch { alert("Network error."); }
    setClearing(false);
  }

  const filterOptions = [
    { value: "all", label: "All" },
    { value: "property", label: "Properties" },
    { value: "vehicle", label: "Vehicles" },
  ];

  return (
    <div>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Listings Inspector</h1>
          <p className={styles.subtitle}>View, filter, and manage all platform listings.</p>
        </div>
        <div className={styles.headerActions}>
          <button onClick={loadListings} className={styles.refreshBtn} disabled={loading}>↻ Refresh</button>
          <button onClick={handleClearAll} className={styles.clearBtn} disabled={clearing || loading}>
            {clearing ? "Clearing…" : "🗑️ Clear All"}
          </button>
        </div>
      </div>

      <div className={styles.filterTabs}>
        {filterOptions.map(opt => (
          <button
            key={opt.value}
            onClick={() => setFilter(opt.value)}
            className={`${styles.filterTab} ${filter === opt.value ? styles.filterTabActive : ""}`}
          >
            {opt.label}
          </button>
        ))}
      </div>

      {error && <div className={styles.errorBox}>⚠️ {error}</div>}

      {loading && !error && (
        <div className={styles.loadingBox}>
          <div className={styles.spinner} />
          <span>Loading listings…</span>
        </div>
      )}

      {!loading && !error && listings.length === 0 && (
        <div className={styles.emptyBox}>
          <div className={styles.emptyIcon}>📦</div>
          <div>No listings found. Use Quick Seed to add test data.</div>
          <a href="/dashboard/seed" className={styles.seedLink}>Go to Quick Seed →</a>
        </div>
      )}

      {!loading && listings.length > 0 && (
        <div>
          <div className={styles.countBar}>{listings.length} listing(s) found</div>
          <div className={styles.grid}>
            {listings.map(l => (
              <div key={l.id} className={styles.card}>
                <div className={styles.cardImagePlaceholder}>
                  {l.imageUrls?.[0]
                    ? <img src={l.imageUrls[0]} alt={l.title} className={styles.cardImage} />
                    : <span className={styles.noImage}>{l.type === "property" ? "🏠" : "🚗"}</span>
                  }
                  <div className={styles.typeBadge} style={{ background: l.type === "property" ? "#3b82f6" : "#8b5cf6" }}>
                    {l.type}
                  </div>
                  <div className={styles.publishedBadge} style={{ background: l.isPublished ? "#10b981" : "#f59e0b" }}>
                    {l.isPublished ? "PUBLIC" : "DRAFT"}
                  </div>
                </div>
                <div className={styles.cardBody}>
                  <div className={styles.cardTitle}>{l.title}</div>
                  <div className={styles.cardMeta}>
                    <span>📍 {l.city}</span>
                    <span>💰 Le {l.price?.toLocaleString()}</span>
                  </div>
                  {l.ownerName && <div className={styles.cardOwner}>👤 {l.ownerName}</div>}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
