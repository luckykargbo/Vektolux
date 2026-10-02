"use client";
// src/app/dashboard/fees/page.tsx — Fees & Commissions (admin-controlled fee rules, versioned + audited)
import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Payer = "buyer" | "owner";
interface Terms {
  ownerFeeBps: number;
  buyerFeeBps: number;
  agentCommissionBps: number;
  agentCommissionPayer: Payer;
  platformShareOfAgentCommissionBps: number;
}
interface RuleRow extends Terms {
  id: string;
  version: number;
  status: "active" | "cancelled";
  inEffect: boolean;
  effectiveFrom: number;
  note: string;
  createdAt: number;
  createdByName: string | null;
  cancelledAt: number | null;
  cancelledByName: string | null;
  cancelReason: string | null;
}
interface Vertical {
  vertical: string;
  label: string;
  agentCapable: boolean;
  ownerFeeBase: "base" | "buyer_total";
  defaults: Terms;
  current: Terms & { source: "default" | "configured"; version: number; ruleId: string | null };
  example: {
    baseAmount: number;
    buyerFee: number;
    ownerFee: number;
    agentCommissionGross: number;
    agentCommissionNet: number;
    platformAgentShare: number;
    platformTotal: number;
    buyerTotal: number;
    payeeNet: number;
  };
  scheduled: RuleRow[];
  history: RuleRow[];
}
interface AuditRow {
  action: "FEE_RULE_CHANGED" | "FEE_RULE_CANCELLED";
  at: number;
  adminName: string | null;
  vertical: string | null;
  version: number | null;
  effectiveFrom: number | null;
  previous: (Terms & { version?: number }) | null;
  next: Terms | null;
  note: string | null;
}
interface Data {
  now: number;
  verticals: Vertical[];
  audit: AuditRow[];
}

const pct = (bps: number) => `${(bps / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })}%`;
const money = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const when = (ms: number | null) => (ms ? new Date(ms).toLocaleString() : "—");
const termsLine = (t: Terms, agentCapable: boolean) =>
  `buyer ${pct(t.buyerFeeBps)} · owner ${pct(t.ownerFeeBps)}` +
  (agentCapable ? ` · agent ${pct(t.agentCommissionBps)} (paid by ${t.agentCommissionPayer}) · platform share ${pct(t.platformShareOfAgentCommissionBps)}` : "");

function Editor({ v, onSaved }: { v: Vertical; onSaved: () => void }) {
  const [form, setForm] = useState({
    buyer: String(v.current.buyerFeeBps / 100),
    owner: String(v.current.ownerFeeBps / 100),
    agent: String(v.current.agentCommissionBps / 100),
    payer: v.current.agentCommissionPayer as Payer,
    share: String(v.current.platformShareOfAgentCommissionBps / 100),
    when: "now" as "now" | "scheduled",
    at: "",
    note: "",
  });
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const bps = (s: string) => Math.round(Number(s) * 100);

  async function save() {
    setMsg("");
    const effectiveFrom = form.when === "scheduled" ? new Date(form.at).getTime() : undefined;
    if (form.when === "scheduled" && !Number.isFinite(effectiveFrom)) {
      setMsg("Choose the date and time the new fees take effect.");
      return;
    }
    const values = [form.buyer, form.owner, form.agent, form.share].map(Number);
    if (values.some((n) => !Number.isFinite(n) || n < 0)) {
      setMsg("Percentages must be numbers of 0 or more.");
      return;
    }
    const summary =
      `${v.label}: buyer ${form.buyer}%, owner ${form.owner}%` +
      (v.agentCapable ? `, agent ${form.agent}% (paid by ${form.payer}), platform share ${form.share}%` : "") +
      `, effective ${form.when === "now" ? "immediately" : new Date(effectiveFrom!).toLocaleString()}.\n\n` +
      "Existing orders keep the fees they were priced with. Continue?";
    if (!window.confirm(summary)) return;
    setBusy(true);
    try {
      const res = await adminFetch("/api/fee-rules", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "set",
          vertical: v.vertical,
          buyerFeeBps: bps(form.buyer),
          ownerFeeBps: bps(form.owner),
          agentCommissionBps: v.agentCapable ? bps(form.agent) : 0,
          agentCommissionPayer: form.payer,
          platformShareOfAgentCommissionBps: v.agentCapable ? bps(form.share) : 0,
          effectiveFrom,
          note: form.note,
        }),
      });
      const body = await res.json();
      if (body.success) {
        setMsg(`Saved as version ${body.data.version}.`);
        onSaved();
      } else setMsg(body.error ?? "Could not save.");
    } catch {
      setMsg("Network connection error");
    }
    setBusy(false);
  }

  const field = (label: string, key: "buyer" | "owner" | "agent" | "share") => (
    <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13 }}>
      {label}
      <input type="number" min={0} step={0.01} value={form[key]} onChange={(e) => setForm({ ...form, [key]: e.target.value })} style={{ padding: 6, width: 110 }} />
    </label>
  );

  return (
    <div style={{ borderTop: "1px solid #e2e8f0", padding: 16, display: "flex", flexDirection: "column", gap: 12 }}>
      <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
        {field("Buyer fee (%)", "buyer")}
        {field(v.ownerFeeBase === "buyer_total" ? "Platform commission (% of buyer total)" : "Owner fee (%)", "owner")}
        {v.agentCapable && field("Agent commission (%)", "agent")}
        {v.agentCapable && (
          <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13 }}>
            Commission paid by
            <select value={form.payer} onChange={(e) => setForm({ ...form, payer: e.target.value as Payer })} style={{ padding: 6 }}>
              <option value="buyer">Buyer (added on top)</option>
              <option value="owner">Owner (deducted)</option>
            </select>
          </label>
        )}
        {v.agentCapable && field("Platform share of commission (%)", "share")}
      </div>
      <div style={{ display: "flex", gap: 16, flexWrap: "wrap", alignItems: "center", fontSize: 13 }}>
        <label>
          <input type="radio" checked={form.when === "now"} onChange={() => setForm({ ...form, when: "now" })} /> Effective now
        </label>
        <label>
          <input type="radio" checked={form.when === "scheduled"} onChange={() => setForm({ ...form, when: "scheduled" })} /> Schedule for
        </label>
        <input type="datetime-local" value={form.at} disabled={form.when !== "scheduled"} onChange={(e) => setForm({ ...form, at: e.target.value })} style={{ padding: 6 }} />
      </div>
      <label style={{ display: "flex", flexDirection: "column", gap: 4, fontSize: 13 }}>
        Reason / note (required, kept in the audit log)
        <textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} rows={2} style={{ padding: 6 }} />
      </label>
      <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
        <button className={`${styles.actionBtn} ${styles.actionBtnPrimary}`} onClick={save} disabled={busy || form.note.trim().length < 5}>
          Save new version
        </button>
        {msg && <span style={{ fontSize: 13 }}>{msg}</span>}
      </div>
    </div>
  );
}

function VerticalCard({ v, now, onChanged }: { v: Vertical; now: number; onChanged: () => void }) {
  const [editing, setEditing] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [msg, setMsg] = useState("");
  const ex = v.example;

  async function cancel(rule: RuleRow) {
    const reason = window.prompt(`Cancel the scheduled version ${rule.version} (effective ${when(rule.effectiveFrom)})? Reason:`);
    if (reason === null) return;
    try {
      const res = await adminFetch("/api/fee-rules", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "cancel", ruleId: rule.id, reason }),
      });
      const body = await res.json();
      setMsg(body.success ? `Version ${rule.version} cancelled.` : body.error ?? "Could not cancel.");
      if (body.success) onChanged();
    } catch {
      setMsg("Network connection error");
    }
  }

  return (
    <div className={styles.tableCard} style={{ marginBottom: 16 }}>
      <div className={styles.tableHeader}>
        <div>
          <div className={styles.tableTitle}>{v.label}</div>
          <div className={styles.statSub}>
            In effect: {v.current.source === "default" ? "built-in default (no rule set yet)" : `version ${v.current.version}`}
          </div>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <button className={styles.actionBtn} onClick={() => setShowHistory(!showHistory)}>
            {showHistory ? "Hide" : "Show"} previous versions
          </button>
          <button className={`${styles.actionBtn} ${styles.actionBtnEmerald}`} onClick={() => setEditing(!editing)}>
            {editing ? "Close" : "Change fees"}
          </button>
        </div>
      </div>

      <table className={styles.table}>
        <thead>
          <tr>
            <th>Buyer fee</th>
            <th>{v.ownerFeeBase === "buyer_total" ? "Platform commission" : "Owner fee"}</th>
            <th>Agent commission</th>
            <th>Platform share of commission</th>
            <th>Example on 1,000</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>{pct(v.current.buyerFeeBps)}</td>
            <td>
              {pct(v.current.ownerFeeBps)}
              {v.ownerFeeBase === "buyer_total" && <div className={styles.statSub}>of what the buyer pays</div>}
            </td>
            <td>
              {v.agentCapable ? (
                <>
                  {pct(v.current.agentCommissionBps)}
                  <div className={styles.statSub}>paid by {v.current.agentCommissionPayer}; only with an owner-authorised agent</div>
                </>
              ) : (
                <span className={styles.statSub}>Not available for this flow</span>
              )}
            </td>
            <td>{v.agentCapable ? pct(v.current.platformShareOfAgentCommissionBps) : "—"}</td>
            <td style={{ fontSize: 13 }}>
              Buyer pays {money(ex.buyerTotal)}
              <br />
              Owner receives {money(ex.payeeNet)}
              {v.agentCapable && (
                <>
                  <br />
                  Agent receives {money(ex.agentCommissionNet)}
                </>
              )}
              <br />
              Platform keeps {money(ex.platformTotal)}
            </td>
          </tr>
        </tbody>
      </table>

      {v.scheduled.length > 0 && (
        <div style={{ padding: "12px 16px" }}>
          <div className={styles.statLabel}>Scheduled</div>
          {v.scheduled.map((r) => (
            <div key={r.id} style={{ display: "flex", gap: 12, alignItems: "center", fontSize: 13, padding: "6px 0", flexWrap: "wrap" }}>
              <span className={`${styles.badge} ${styles.badgeHeld}`}>v{r.version}</span>
              <span>from {when(r.effectiveFrom)}</span>
              <span>{termsLine(r, v.agentCapable)}</span>
              <span className={styles.statSub}>by {r.createdByName ?? "—"}: “{r.note}”</span>
              {r.effectiveFrom > now && (
                <button className={styles.actionBtn} onClick={() => cancel(r)}>
                  Cancel scheduled
                </button>
              )}
            </div>
          ))}
        </div>
      )}
      {msg && <p style={{ padding: "0 16px", fontSize: 13 }}>{msg}</p>}

      {showHistory && (
        <div style={{ overflowX: "auto" }}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Version</th>
                <th>Status</th>
                <th>Effective from</th>
                <th>Terms</th>
                <th>Changed by</th>
                <th>Reason / note</th>
              </tr>
            </thead>
            <tbody>
              {v.history.length === 0 && (
                <tr>
                  <td colSpan={6} className={styles.statSub}>
                    No changes yet — the built-in defaults apply: {termsLine(v.defaults, v.agentCapable)}
                  </td>
                </tr>
              )}
              {v.history.map((r) => (
                <tr key={r.id}>
                  <td>v{r.version}</td>
                  <td>
                    {r.status === "cancelled" ? (
                      <span className={`${styles.badge} ${styles.badgeDisputed}`}>Cancelled</span>
                    ) : r.inEffect ? (
                      <span className={`${styles.badge} ${styles.badgeSettled}`}>In effect</span>
                    ) : r.effectiveFrom > now ? (
                      <span className={`${styles.badge} ${styles.badgeHeld}`}>Scheduled</span>
                    ) : (
                      <span className={`${styles.badge} ${styles.badgeReleased}`}>Superseded</span>
                    )}
                  </td>
                  <td>{when(r.effectiveFrom)}</td>
                  <td style={{ fontSize: 13 }}>{termsLine(r, v.agentCapable)}</td>
                  <td style={{ fontSize: 13 }}>
                    {r.createdByName ?? "—"}
                    <div className={styles.statSub}>{when(r.createdAt)}</div>
                  </td>
                  <td style={{ fontSize: 13 }}>
                    {r.note}
                    {r.status === "cancelled" && (
                      <div className={styles.statSub}>
                        Cancelled by {r.cancelledByName ?? "—"} on {when(r.cancelledAt)}: {r.cancelReason ?? ""}
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {editing && (
        <Editor
          v={v}
          onSaved={() => {
            setEditing(false);
            onChanged();
          }}
        />
      )}
    </div>
  );
}

export default function FeesPage() {
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch("/api/fee-rules");
      const body = await res.json();
      if (body.success) setData(body.data);
      else setError(body.error ?? "Could not load fee rules.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const labelOf = (vertical: string | null) => data?.verticals.find((x) => x.vertical === vertical)?.label ?? vertical ?? "—";

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Fees &amp; Commissions</h1>
          <p className={styles.subtitle}>
            Every change is a new version with an effective date, a reason and an audit record. Rules can be scheduled and
            cancelled until they take effect.
          </p>
        </div>
        <button className={styles.refreshBtn} onClick={load} disabled={loading}>
          <RefreshCcw size={16} /> Refresh
        </button>
      </div>

      <div style={{ background: "#eff6ff", border: "1px solid #bfdbfe", color: "#1e3a8a", borderRadius: 12, padding: "12px 16px", marginBottom: 20, fontSize: 14 }}>
        <strong>Changing a fee does not change existing orders.</strong> Each order stores the fees it was priced with when it
        was created; new rules apply only to orders created after the rule takes effect.
      </div>

      {error && <p style={{ color: "#dc2626" }}>{error}</p>}
      {data?.verticals.map((v) => (
        <VerticalCard key={v.vertical} v={v} now={data.now} onChanged={load} />
      ))}

      {data && (
        <div className={styles.tableCard}>
          <div className={styles.tableHeader}>
            <div className={styles.tableTitle}>Audit history</div>
          </div>
          <div style={{ overflowX: "auto" }}>
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>When</th>
                  <th>Admin</th>
                  <th>Action</th>
                  <th>Flow</th>
                  <th>Change</th>
                  <th>Reason / note</th>
                </tr>
              </thead>
              <tbody>
                {data.audit.length === 0 && (
                  <tr>
                    <td colSpan={6} className={styles.statSub}>
                      No fee changes have been made.
                    </td>
                  </tr>
                )}
                {data.audit.map((a, i) => {
                  const agentCapable = data.verticals.find((x) => x.vertical === a.vertical)?.agentCapable ?? false;
                  return (
                    <tr key={i}>
                      <td>{when(a.at)}</td>
                      <td>{a.adminName ?? "—"}</td>
                      <td>{a.action === "FEE_RULE_CHANGED" ? `New version v${a.version ?? "?"}` : `Cancelled v${a.version ?? "?"}`}</td>
                      <td>{labelOf(a.vertical)}</td>
                      <td style={{ fontSize: 13 }}>
                        {a.previous && a.next ? (
                          <>
                            {termsLine(a.previous, agentCapable)}
                            <br />→ {termsLine(a.next, agentCapable)}
                            <div className={styles.statSub}>effective {when(a.effectiveFrom)}</div>
                          </>
                        ) : (
                          <span className={styles.statSub}>scheduled for {when(a.effectiveFrom)}</span>
                        )}
                      </td>
                      <td style={{ fontSize: 13 }}>{a.note ?? ""}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
