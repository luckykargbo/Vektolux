"use client";
// src/app/dashboard/listing-agents/page.tsx — Owner-authorised listing agents (read + admin revoke)
import { Fragment, useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Status = "pending" | "active" | "declined" | "revoked";
interface Person {
  name: string;
  email: string | null;
}
interface Row {
  id: string;
  listingType: "property" | "vehicle";
  listingId: string;
  listingTitle: string | null;
  listingOwnerChanged: boolean | null;
  owner: Person | null;
  agent: Person | null;
  status: Status;
  invitedAt: number;
  acceptedAt: number | null;
  declinedAt: number | null;
  revokedAt: number | null;
  revokedByRole: "owner" | "agent" | "admin" | null;
  revokedByName: string | null;
  revokeReason: string | null;
  events: { action: string; actorRole: string; actorName: string | null; note: string | null; at: number }[];
  orders: { kind: "contract" | "viewing_pass"; id: string; code: string; type: string; amount: number; agentCommission: number; state: string; createdAt: number }[];
}

const when = (ms: number | null) => (ms ? new Date(ms).toLocaleString() : "—");
const money = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const BADGE: Record<Status, string> = {
  pending: styles.badgeHeld,
  active: styles.badgeSettled,
  declined: styles.badgeReleased,
  revoked: styles.badgeDisputed,
};

export default function ListingAgentsPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [filter, setFilter] = useState<"" | Status>("");
  const [open, setOpen] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch(`/api/listing-agents${filter ? `?status=${filter}` : ""}`);
      const body = await res.json();
      if (body.success) setRows(body.data);
      else setError(body.error ?? "Could not load listing agents.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, [filter]);

  useEffect(() => {
    load();
  }, [load]);

  async function revoke(r: Row) {
    const reason = window.prompt(`Revoke ${r.agent?.name ?? "this agent"} for "${r.listingTitle ?? r.listingId}"? Reason (required, audited):`);
    if (reason === null) return;
    setMsg("");
    try {
      const res = await adminFetch("/api/listing-agents", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "revoke", authorizationId: r.id, reason }),
      });
      const body = await res.json();
      setMsg(body.success ? "Authorisation revoked." : body.error ?? "Could not revoke.");
      if (body.success) load();
    } catch {
      setMsg("Network connection error");
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Listing Agents</h1>
          <p className={styles.subtitle}>
            Owner → authorises Agent → Agent represents that listing. Agent commission is charged only while an authorisation is
            active; orders keep the terms they were priced with.
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <select value={filter} onChange={(e) => setFilter(e.target.value as "" | Status)} style={{ padding: 8, borderRadius: 8 }}>
            <option value="">All statuses</option>
            <option value="pending">Pending</option>
            <option value="active">Active</option>
            <option value="declined">Declined</option>
            <option value="revoked">Revoked</option>
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
                <th>Listing</th>
                <th>Owner</th>
                <th>Agent</th>
                <th>Status</th>
                <th>Authorised</th>
                <th>Accepted</th>
                <th>Revoked</th>
                <th>Orders</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && !loading && (
                <tr>
                  <td colSpan={9} className={styles.statSub}>
                    No listing-agent authorisations.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <Fragment key={r.id}>
                  <tr>
                    <td>
                      {r.listingTitle ?? <span className={styles.statSub}>Listing removed</span>}
                      <div className={styles.statSub}>
                        {r.listingType} · {r.listingId}
                      </div>
                      {r.listingOwnerChanged && <div style={{ color: "#d97706", fontSize: 12 }}>Listing owner changed — not valid</div>}
                    </td>
                    <td>
                      {r.owner?.name ?? "—"}
                      <div className={styles.statSub}>{r.owner?.email ?? ""}</div>
                    </td>
                    <td>
                      {r.agent?.name ?? "—"}
                      <div className={styles.statSub}>{r.agent?.email ?? ""}</div>
                    </td>
                    <td>
                      <span className={`${styles.badge} ${BADGE[r.status]}`}>{r.status}</span>
                    </td>
                    <td>{when(r.invitedAt)}</td>
                    <td>{r.status === "declined" ? `Declined ${when(r.declinedAt)}` : when(r.acceptedAt)}</td>
                    <td style={{ fontSize: 13 }}>
                      {r.revokedAt ? (
                        <>
                          {when(r.revokedAt)}
                          <div className={styles.statSub}>
                            by {r.revokedByName ?? "—"} ({r.revokedByRole}): {r.revokeReason}
                          </div>
                        </>
                      ) : (
                        "—"
                      )}
                    </td>
                    <td>{r.orders.length}</td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      <button className={styles.actionBtn} onClick={() => setOpen(open === r.id ? null : r.id)}>
                        {open === r.id ? "Hide" : "Details"}
                      </button>{" "}
                      {(r.status === "pending" || r.status === "active") && (
                        <button className={styles.actionBtn} onClick={() => revoke(r)}>
                          Revoke
                        </button>
                      )}
                    </td>
                  </tr>
                  {open === r.id && (
                    <tr>
                      <td colSpan={9} style={{ background: "#f8fafc" }}>
                        <div className={styles.statLabel}>Audit trail</div>
                        {r.events.map((e, i) => (
                          <div key={i} style={{ fontSize: 13, padding: "2px 0" }}>
                            {when(e.at)} — <strong>{e.action}</strong> by {e.actorName ?? "—"} ({e.actorRole}){e.note ? `: ${e.note}` : ""}
                          </div>
                        ))}
                        <div className={styles.statLabel} style={{ marginTop: 10 }}>
                          Associated orders
                        </div>
                        {r.orders.length === 0 && <div className={styles.statSub}>No orders relied on this authorisation.</div>}
                        {r.orders.map((o) => (
                          <div key={o.id} style={{ fontSize: 13, padding: "2px 0" }}>
                            {when(o.createdAt)} — {o.code} · {o.type} · total {money(o.amount)} · agent {money(o.agentCommission)} · {o.state}
                          </div>
                        ))}
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
