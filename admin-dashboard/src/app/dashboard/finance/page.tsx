"use client";
// src/app/dashboard/finance/page.tsx — Financial overview (real Convex data, categories kept separate)
import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import styles from "../escrow/escrow.module.css";
import { adminFetch } from "@/lib/adminSession";

type Bucket = { amount: number; count: number };
type ByCurrency = Record<string, Bucket>;
interface Overview {
  generatedAt: number;
  userFunds: Record<string, { available: number; escrow: number; pending: number; wallets: number }>;
  depositsAwaitingConfirmation: ByCurrency;
  depositsSettled: ByCurrency;
  withdrawals: Record<string, ByCurrency>;
  refunds: ByCurrency;
  subscriptionRevenue: ByCurrency;
  platformFees: ByCurrency;
  activeSubscriptions: number;
  truncated: string[];
}

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function Amounts({ m }: { m: ByCurrency | undefined }) {
  const entries = Object.entries(m ?? {});
  if (entries.length === 0) return <span>0.00</span>;
  return (
    <>
      {entries.map(([c, b]) => (
        <div key={c}>
          {c} {fmt(b.amount)} <span className={styles.statSub}>({b.count})</span>
        </div>
      ))}
    </>
  );
}

function Card({ label, sub, children }: { label: string; sub: string; children: React.ReactNode }) {
  return (
    <div className={styles.statCard}>
      <div className={styles.statLabel}>{label}</div>
      <div className={styles.statValue}>{children}</div>
      <div className={styles.statSub}>{sub}</div>
    </div>
  );
}

export default function FinancePage() {
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const res = await adminFetch("/api/finance");
      const body = await res.json();
      if (body.success) setData(body.data);
      else setError(body.error ?? "Could not load the financial overview.");
    } catch {
      setError("Network connection error");
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const funds = Object.entries(data?.userFunds ?? {});

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Financial Overview</h1>
          <p className={styles.subtitle}>
            Computed live from the ledger and wallets. User funds are held for users and are not platform revenue.
          </p>
        </div>
        <button className={styles.refreshBtn} onClick={load} disabled={loading}>
          <RefreshCcw size={16} /> Refresh
        </button>
      </div>

      {error && <p style={{ color: "#dc2626" }}>{error}</p>}
      {data && data.truncated.length > 0 && (
        <p style={{ color: "#d97706" }}>Partial figures (too many records in one query): {data.truncated.join(", ")}</p>
      )}

      {data && (
        <>
          <h2 className={styles.tableTitle}>User funds (liabilities)</h2>
          <div className={styles.statsGrid}>
            {funds.length === 0 && <Card label="Available" sub="No wallets yet">0.00</Card>}
            {funds.map(([c, f]) => (
              <div key={c} style={{ display: "contents" }}>
                <Card label={`Available (${c})`} sub={`${f.wallets} wallets — withdrawable`}>{fmt(f.available)}</Card>
                <Card label={`Held in escrow (${c})`} sub="Protected until release/refund">{fmt(f.escrow)}</Card>
                <Card label={`Pending (${c})`} sub="Not yet available">{fmt(f.pending)}</Card>
              </div>
            ))}
          </div>

          <h2 className={styles.tableTitle}>Money movement</h2>
          <div className={styles.statsGrid}>
            <Card label="Deposits awaiting provider" sub="Not credited until verified"><Amounts m={data.depositsAwaitingConfirmation} /></Card>
            <Card label="Deposits settled" sub="Verified and credited"><Amounts m={data.depositsSettled} /></Card>
            <Card label="Withdrawals in flight" sub="Pending + processing">
              <Amounts m={data.withdrawals.pending} />
              <Amounts m={data.withdrawals.processing} />
            </Card>
            <Card label="Withdrawals completed" sub="Confirmed by provider"><Amounts m={data.withdrawals.completed} /></Card>
            <Card label="Withdrawals failed" sub="Funds returned to wallet"><Amounts m={data.withdrawals.failed} /></Card>
            <Card label="Refunds" sub="Completed refunds"><Amounts m={data.refunds} /></Card>
          </div>

          <h2 className={styles.tableTitle}>Platform revenue</h2>
          <div className={styles.statsGrid}>
            <Card label="Subscription revenue" sub={`${data.activeSubscriptions} active subscriptions`}><Amounts m={data.subscriptionRevenue} /></Card>
            <Card label="Platform fees / commission" sub="Realised on escrow release"><Amounts m={data.platformFees} /></Card>
          </div>
          <p className={styles.statSub}>Generated {new Date(data.generatedAt).toLocaleString()}</p>
        </>
      )}
    </div>
  );
}
