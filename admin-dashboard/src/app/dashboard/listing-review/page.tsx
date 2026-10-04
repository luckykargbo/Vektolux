"use client";
// src/app/dashboard/listing-review/page.tsx — Real-estate listing moderation (admin review queue)
import { Fragment, useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Filter = "pending_review" | "approved" | "rejected" | "removed" | "all";
type Decision = "approve" | "reject" | "remove" | "archive";

interface Row {
  id: string;
  title: string;
  category: string;
  price: number;
  hourlyRate: number | null;
  currency: string;
  publicLocation: string;
  coverImage: string | null;
  photoCount: number;
  videoCount: number;
  ownerName: string;
  ownerTitle: string;
  moderationStatus: string | null;
  lifecycleStatus: string;
  isPublic: boolean;
  moderationReason: string | null;
  submittedForReviewAt: number | null;
  moderatedAt: number | null;
  createdAt: number;
}

interface Detail {
  id: string;
  title: string;
  description: string;
  category: string;
  price: number;
  hourlyRate: number | null;
  currency: string;
  bedrooms: number | null;
  bathrooms: number | null;
  areaSqM: number | null;
  amenities: string[];
  imageUrls: string[];
  videoUrls: string[];
  publicLocation: string;
  privateAddress: string;
  privateContactPhone: string | null;
  owner: { id: string; name: string; title: string; roleApproved: boolean } | null;
  agent: { id: string; name: string } | null;
  lifecycleStatus: string;
  moderationReason: string | null;
  history: { action: string; at: number; reason: string | null }[];
}

const when = (ms: number | null) => (ms ? new Date(ms).toLocaleString() : "—");
const money = (n: number, c: string) => `${c} ${n.toLocaleString()}`;
const LABEL: Record<string, string> = {
  active: "Active",
  pending_review: "Pending review",
  rejected: "Rejected",
  removed: "Removed",
  draft: "Draft",
  unpublished: "Unpublished",
  off_market: "Off-market",
  archived: "Archived",
};
const BADGE: Record<string, string> = {
  active: styles.badgeSettled,
  pending_review: styles.badgeHeld,
  rejected: styles.badgeDisputed,
  removed: styles.badgeDisputed,
  archived: styles.badgeReleased,
};
const DECISION_TEXT: Record<Decision, { label: string; needsReason: boolean; confirm: string }> = {
  approve: { label: "Approve", needsReason: false, confirm: "Approve this listing? It becomes public immediately." },
  reject: { label: "Reject", needsReason: true, confirm: "Reject this listing. The agent sees your reason and can edit and resubmit." },
  remove: { label: "Remove", needsReason: true, confirm: "Remove this listing for good. The owner sees your reason." },
  archive: { label: "Archive", needsReason: false, confirm: "Archive this listing (off the marketplace; the owner can restore it as a draft)." },
};

export default function ListingReviewPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [filter, setFilter] = useState<Filter>("pending_review");
  const [open, setOpen] = useState<string | null>(null);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch(`/api/listing-review?moderation=${filter}`);
      const body = await res.json();
      if (body.success) setRows(body.data ?? []);
      else setError(body.error ?? "Could not load listings.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, [filter]);

  useEffect(() => {
    load();
  }, [load]);

  async function toggle(id: string) {
    if (open === id) {
      setOpen(null);
      setDetail(null);
      return;
    }
    setOpen(id);
    setDetail(null);
    try {
      const res = await adminFetch(`/api/listing-review?id=${encodeURIComponent(id)}`);
      const body = await res.json();
      if (body.success) setDetail(body.data);
      else setMsg(body.error ?? "Could not open the listing.");
    } catch {
      setMsg("Network connection error");
    }
  }

  async function decide(id: string, decision: Decision) {
    const text = DECISION_TEXT[decision];
    let reason: string | undefined;
    if (text.needsReason) {
      const input = window.prompt(`${text.confirm}\n\nReason (required, at least 5 characters, shown to the owner):`);
      if (input === null) return;
      reason = input.trim();
    } else if (!window.confirm(text.confirm)) {
      return;
    }
    setBusy(true);
    setMsg("");
    try {
      const res = await adminFetch("/api/listing-review", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ listingId: id, decision, ...(reason ? { reason } : {}) }),
      });
      const body = await res.json();
      setMsg(body.success ? `${text.label}d.`.replace("Archived.", "Archived.").replace("Removed.", "Removed.") : body.error ?? "Could not save the decision.");
      if (body.success) {
        setOpen(null);
        setDetail(null);
        load();
      }
    } catch {
      setMsg("Network connection error");
    }
    setBusy(false);
  }

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Listing Review</h1>
          <p className={styles.subtitle}>
            Listings from Real Estate Agents wait here before they go live. Rejecting or removing needs a reason; every decision is
            audited and the owner is notified.
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <select value={filter} onChange={(e) => setFilter(e.target.value as Filter)} style={{ padding: 8, borderRadius: 8 }}>
            <option value="pending_review">Pending review</option>
            <option value="approved">Approved / live</option>
            <option value="rejected">Rejected</option>
            <option value="removed">Removed</option>
            <option value="all">All (latest)</option>
          </select>
          <button className={styles.refreshBtn} onClick={load} disabled={loading}>
            <RefreshCcw size={16} /> Refresh
          </button>
        </div>
      </div>

      {error && <p style={{ color: "#dc2626" }}>{error}</p>}
      {msg && <p style={{ fontSize: 14 }}>{msg}</p>}

      <div className={styles.tableCard}>
        <div style={{ overflowX: "auto" }}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th />
                <th>Listing</th>
                <th>Owner</th>
                <th>Price</th>
                <th>Media</th>
                <th>Status</th>
                <th>Submitted</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !loading && (
                <tr>
                  <td colSpan={8} className={styles.statSub}>
                    {filter === "pending_review" ? "Nothing is waiting for review." : "No listings."}
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <Fragment key={r.id}>
                  <tr>
                    <td style={{ width: 64 }}>
                      {r.coverImage ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={r.coverImage} alt="" style={{ width: 56, height: 42, objectFit: "cover", borderRadius: 6 }} />
                      ) : (
                        <div style={{ width: 56, height: 42, background: "#e2e8f0", borderRadius: 6 }} />
                      )}
                    </td>
                    <td>
                      {r.title}
                      <div className={styles.statSub}>
                        {r.category.replace(/_/g, " ")} · {r.publicLocation}
                      </div>
                    </td>
                    <td>
                      {r.ownerName}
                      <div className={styles.statSub}>{r.ownerTitle}</div>
                    </td>
                    <td>{money(r.hourlyRate ?? r.price, r.currency)}</td>
                    <td>
                      {r.photoCount} photo{r.photoCount === 1 ? "" : "s"}
                      {r.videoCount > 0 ? ` · ${r.videoCount} video${r.videoCount === 1 ? "" : "s"}` : ""}
                    </td>
                    <td>
                      <span className={`${styles.badge} ${BADGE[r.lifecycleStatus] ?? styles.badgeReleased}`}>
                        {LABEL[r.lifecycleStatus] ?? r.lifecycleStatus}
                      </span>
                      {r.moderationReason && <div className={styles.statSub}>{r.moderationReason}</div>}
                    </td>
                    <td>{when(r.submittedForReviewAt ?? r.createdAt)}</td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      <button className={styles.actionBtn} onClick={() => toggle(r.id)}>
                        {open === r.id ? "Close" : "Review"}
                      </button>
                    </td>
                  </tr>
                  {open === r.id && (
                    <tr>
                      <td colSpan={8} style={{ background: "#f8fafc" }}>
                        {!detail ? (
                          <div className={styles.statSub}>Loading…</div>
                        ) : (
                          <div style={{ display: "grid", gap: 12 }}>
                            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                              {detail.imageUrls.map((u) => (
                                // eslint-disable-next-line @next/next/no-img-element
                                <img key={u} src={u} alt="" style={{ height: 120, borderRadius: 8, objectFit: "cover" }} />
                              ))}
                              {detail.imageUrls.length === 0 && <span className={styles.statSub}>No photos.</span>}
                            </div>
                            {detail.videoUrls.length > 0 && (
                              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                                {detail.videoUrls.map((u) => (
                                  <video key={u} src={u} controls preload="metadata" style={{ height: 160, borderRadius: 8, background: "#000" }} />
                                ))}
                              </div>
                            )}
                            <div style={{ fontSize: 14 }}>
                              <strong>{detail.title}</strong> — {money(detail.hourlyRate ?? detail.price, detail.currency)} ·{" "}
                              {detail.bedrooms ?? "—"} bed · {detail.bathrooms ?? "—"} bath · {detail.areaSqM ? `${detail.areaSqM} m²` : "size n/a"}
                              <p style={{ margin: "6px 0" }}>{detail.description}</p>
                              {detail.amenities.length > 0 && <div className={styles.statSub}>{detail.amenities.join(" · ")}</div>}
                            </div>
                            <div style={{ fontSize: 13 }}>
                              <div>
                                <strong>Public location:</strong> {detail.publicLocation}
                              </div>
                              <div>
                                <strong>Private address (admin only):</strong> {detail.privateAddress}
                                {detail.privateContactPhone ? ` · ${detail.privateContactPhone}` : ""}
                              </div>
                              <div>
                                <strong>Owner:</strong> {detail.owner?.name ?? "—"} ({detail.owner?.title ?? "—"})
                                {detail.owner && !detail.owner.roleApproved ? " — role NOT approved" : ""}
                                {detail.agent ? ` · authorised agent: ${detail.agent.name}` : ""}
                              </div>
                            </div>
                            {detail.history.length > 0 && (
                              <div style={{ fontSize: 13 }}>
                                <div className={styles.statLabel}>History</div>
                                {detail.history.map((h, i) => (
                                  <div key={i}>
                                    {when(h.at)} — <strong>{h.action.replace("LISTING_", "").toLowerCase()}</strong>
                                    {h.reason ? `: ${h.reason}` : ""}
                                  </div>
                                ))}
                              </div>
                            )}
                            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                              {detail.lifecycleStatus === "pending_review" && (
                                <>
                                  <button className={styles.actionBtn} disabled={busy} onClick={() => decide(detail.id, "approve")}>
                                    Approve
                                  </button>
                                  <button className={styles.actionBtn} disabled={busy} onClick={() => decide(detail.id, "reject")}>
                                    Reject…
                                  </button>
                                </>
                              )}
                              {detail.lifecycleStatus !== "removed" && (
                                <button className={styles.actionBtn} disabled={busy} onClick={() => decide(detail.id, "remove")}>
                                  Remove…
                                </button>
                              )}
                              {detail.lifecycleStatus !== "removed" && detail.lifecycleStatus !== "archived" && (
                                <button className={styles.actionBtn} disabled={busy} onClick={() => decide(detail.id, "archive")}>
                                  Archive
                                </button>
                              )}
                            </div>
                          </div>
                        )}
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
