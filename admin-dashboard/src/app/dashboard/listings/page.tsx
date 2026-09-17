"use client";
// src/app/dashboard/listings/page.tsx — Listings Inspector
import { RefreshCcw, Trash2, PackageSearch, Building2, Car, MapPin, Banknote, User, AlertTriangle, CheckCircle2, Ban } from "lucide-react";
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
  const [takingDown, setTakingDown] = useState<string | null>(null);
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
    if (!confirm("This will permanently delete ALL properties and vehicles from the database. Are you absolutely sure?")) return;
    setClearing(true);
    try {
      const res = await fetch("/api/listings", { method: "DELETE" });
      const data = await res.json();
      if (data.success) { setListings([]); alert("All listings cleared!"); }
      else alert("Failed: " + (data.error ?? "Unknown error"));
    } catch { alert("Network error."); }
    setClearing(false);
  }

  async function handleTakeDown(listingId: string, listingType: string) {
    if (!session) return;
    const reason = prompt("Enter reason for taking down this listing:");
    if (reason === null) return;
    
    setTakingDown(listingId);
    try {
      const res = await fetch("/api/listings/takedown", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          adminId: session.user.id,
          sessionToken: session.user.sessionToken,
          listingId,
          listingType,
          reason: reason || "Violation of terms"
        })
      });
      const data = await res.json();
      if (data.success) {
        alert("Listing taken down successfully");
        loadListings();
      } else {
        alert("Failed to take down: " + (data.error ?? "Unknown error"));
      }
    } catch (e) {
      alert("Network error.");
    }
    setTakingDown(null);
  }

  const filterOptions = [
    { value: "all", label: "All" },
    { value: "property", label: "Properties" },
    { value: "car_sale", label: "Car Sales" },
    { value: "car_rental", label: "Auto Rentals" },
    { value: "delivery_van", label: "Delivery Vans" },
    { value: "sand_dump_truck", label: "Sand Dump Trucks" },
    { value: "container_freight_truck", label: "Container Freight" },
  ];

  return (
    <div>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Listings Inspector</h1>
          <p className={styles.subtitle}>View, filter, and manage all platform listings.</p>
        </div>
        <div className={styles.headerActions}>
          <button onClick={loadListings} className={styles.refreshBtn} disabled={loading}><RefreshCcw size={16} style={{display: 'inline', marginRight: 4}} /> Refresh</button>
          <button onClick={handleClearAll} className={styles.clearBtn} disabled={clearing || loading}>
            {clearing ? "Clearing…" : <><Trash2 size={16} style={{display: 'inline', marginRight: 4}} /> Clear All</>}
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

      {error && <div className={styles.errorBox}><AlertTriangle size={16} style={{display: 'inline'}} /> {error}</div>}

      {loading && !error && (
        <div className={styles.loadingBox}>
          <div className={styles.spinner} />
          <span>Loading listings…</span>
        </div>
      )}

      {!loading && !error && listings.length === 0 && (
        <div className={styles.emptyBox}>
          <div className={styles.emptyIcon}><PackageSearch size={32} /></div>
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
                    : <span className={styles.noImage}>{l.type === "property" ? <Building2 size={24} /> : <Car size={24} />}</span>
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
                    <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}><MapPin size={14} /> {l.city}</span>
                    <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}><Banknote size={14} /> Le {l.price?.toLocaleString()}</span>
                  </div>
                  {l.ownerName && <div className={styles.cardOwner} style={{ display: 'flex', alignItems: 'center', gap: 4 }}><User size={14} /> {l.ownerName}</div>}
                  <button 
                    onClick={() => handleTakeDown(l.id, l.type)} 
                    disabled={takingDown === l.id}
                    style={{
                      marginTop: 12,
                      width: '100%',
                      background: '#ef4444',
                      color: 'white',
                      border: 'none',
                      padding: '8px',
                      borderRadius: '4px',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '8px'
                    }}
                  >
                    <Ban size={16} /> {takingDown === l.id ? "Processing..." : "Take Down"}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
