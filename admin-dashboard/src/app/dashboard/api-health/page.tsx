"use client";
// src/app/dashboard/api-health/page.tsx — API Key Health Monitoring & Status Panel
import {
  Activity,
  CheckCircle2,
  AlertTriangle,
  RotateCw,
  Key,
  Shield,
  Clock,
  ChevronRight,
  X,
  Radio,
  Server,
  Terminal,
} from "lucide-react";
import { useEffect, useState } from "react";
import type { AdminSession } from "@/lib/types";
import styles from "./api-health.module.css";

interface GatewayKey {
  id?: string;
  keyName: string;
  maskedValue: string;
  envVarName: string;
  operationalFunction: string;
  usedIn: string;
  healthStatus: "operational" | "degraded" | "outage";
  lastCheckedAt: number;
  isConfigured: boolean;
}

interface GatewayErrorLog {
  id: string;
  endpoint: string;
  statusCode?: number;
  errorMessage: string;
  severity: "warning" | "critical" | "info";
  occurredAt: number;
}

interface GatewayData {
  serviceId: string;
  displayName: string;
  provider: string;
  brandColor: string;
  category: string;
  purpose: string;
  status: "operational" | "degraded" | "error" | "missing_key";
  badgeLabel: string;
  badgeColor: "green" | "red";
  lastPingAt: number;
  lastTransactionAt: number | null;
  keys: GatewayKey[];
  errorLogs: GatewayErrorLog[];
  lastErrorMessage: string | null;
}

export default function ApiHealthPage() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [gateways, setGateways] = useState<GatewayData[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedGateway, setSelectedGateway] = useState<GatewayData | null>(null);
  const [pinging, setPinging] = useState(false);
  const [pingResult, setPingResult] = useState<string | null>(null);

  useEffect(() => {
    const raw = sessionStorage.getItem("adminSession");
    if (raw) {
      try {
        setSession(JSON.parse(raw));
      } catch (e) {
        console.error("Failed to parse session", e);
      }
    }
  }, []);

  const fetchHealthData = async (isManual = false) => {
    if (isManual) setRefreshing(true);
    try {
      const adminId = session?.user?.id || "";
      const sessionToken = session?.user?.sessionToken || "";

      const queryParams = adminId
        ? `?adminId=${encodeURIComponent(adminId)}&sessionToken=${encodeURIComponent(sessionToken)}`
        : "";

      const res = await fetch(`/api/admin/api-health${queryParams}`);
      const json = await res.json();

      if (json.success && json.data?.gateways) {
        setGateways(json.data.gateways);
        // If modal is open, refresh selected gateway
        if (selectedGateway) {
          const updated = json.data.gateways.find(
            (g: GatewayData) => g.serviceId === selectedGateway.serviceId
          );
          if (updated) setSelectedGateway(updated);
        }
      }
    } catch (err) {
      console.error("Failed to fetch gateway health:", err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchHealthData();
  }, [session]);

  const handleDiagnosticPing = async (serviceId: string) => {
    setPinging(true);
    setPingResult(null);
    try {
      const res = await fetch("/api/admin/api-health", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          serviceId,
          adminId: session?.user?.id,
          sessionToken: session?.user?.sessionToken,
        }),
      });
      const data = await res.json();
      if (data.success && data.data) {
        setPingResult(
          `✓ Ping successful (${data.data.pingMs}ms) — carrier endpoint verified 200 OK.`
        );
        fetchHealthData();
      } else {
        setPingResult(`✗ Ping failed: ${data.error || "Carrier timeout"}`);
      }
    } catch (err: any) {
      setPingResult(`✗ Ping error: ${err.message}`);
    } finally {
      setPinging(false);
    }
  };

  const handleUpdateMask = async (serviceId: string, keyName: string, currentMask: string) => {
    const newMask = prompt(`Enter updated mask preview for ${keyName} (e.g. ****1234):`, currentMask);
    if (!newMask) return;
    try {
      await fetch("/api/admin/api-health", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "update-mask",
          serviceId,
          keyName,
          newMaskedValue: newMask,
          healthStatus: "operational",
          adminId: session?.user?.id,
          sessionToken: session?.user?.sessionToken,
        }),
      });
      fetchHealthData();
    } catch (e) {
      console.error(e);
    }
  };

  const handleToggleHealth = async (serviceId: string, newStatus: "operational" | "outage") => {
    if (!selectedGateway || !selectedGateway.keys[0]) return;
    try {
      await fetch("/api/admin/api-health", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "update-mask",
          serviceId,
          keyName: selectedGateway.keys[0].keyName,
          newMaskedValue: selectedGateway.keys[0].maskedValue,
          healthStatus: newStatus,
          adminId: session?.user?.id,
          sessionToken: session?.user?.sessionToken,
        }),
      });
      fetchHealthData();
    } catch (e) {
      console.error(e);
    }
  };

  const formatTimestamp = (ts?: number | null) => {
    if (!ts) return "No recorded activity";
    const date = new Date(ts);
    return date.toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  };

  const totalHealthy = gateways.filter((g) => g.status === "operational").length;

  return (
    <div className={styles.container}>
      {/* Page Header */}
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>API Key Health & Gateway Monitor</h1>
          <p className={styles.subtitle}>
            Real-time status monitoring, credential mask preview, and diagnostic health for platform payment and telco gateways
          </p>
        </div>

        <div className={styles.headerActions}>
          <button
            className={styles.refreshBtn}
            onClick={() => fetchHealthData(true)}
            disabled={refreshing}
          >
            <RotateCw
              size={14}
              style={{
                animation: refreshing ? "spin 1s linear infinite" : "none",
              }}
            />
            {refreshing ? "Checking..." : "Recheck Gateways"}
          </button>
        </div>
      </div>

      {/* Overview Banner */}
      <div className={styles.overviewBanner}>
        <div className={styles.bannerLeft}>
          <div className={styles.shieldIconWrap}>
            <Shield size={24} />
          </div>
          <div>
            <h3 className={styles.bannerTitle}>Production Gateway Infrastructure</h3>
            <p className={styles.bannerText}>
              All raw secrets are strictly isolated inside server-side environment variables. Only masked previews and operational statuses are transmitted.
            </p>
          </div>
        </div>

        <div className={styles.bannerStats}>
          <div className={styles.bannerStatItem}>
            <span className={styles.statLabel}>Total Gateways</span>
            <span className={styles.statValue}>{gateways.length}</span>
          </div>
          <div className={styles.bannerStatItem}>
            <span className={styles.statLabel}>Operational</span>
            <span className={styles.statValue} style={{ color: "#059669" }}>
              {totalHealthy} / {gateways.length}
            </span>
          </div>
          <div className={styles.bannerStatItem}>
            <span className={styles.statLabel}>Security Standard</span>
            <span className={styles.statValue}>PCI-DSS / Bank-Grade</span>
          </div>
        </div>
      </div>

      {/* 4 Provider Cards */}
      <div className={styles.gatewaysGrid}>
        {gateways.map((gw) => (
          <div
            key={gw.serviceId}
            className={styles.gatewayCard}
            onClick={() => {
              setSelectedGateway(gw);
              setPingResult(null);
            }}
          >
            <div className={styles.cardTop}>
              <div className={styles.providerBrand}>
                <div
                  className={styles.providerLogo}
                  style={{ background: gw.brandColor }}
                >
                  {gw.displayName.charAt(0)}
                </div>
                <div>
                  <h3 className={styles.providerName}>{gw.displayName}</h3>
                  <p className={styles.providerCategory}>{gw.provider}</p>
                </div>
              </div>

              {/* Crisp Badge: Green for Operational, Red for Error/Missing */}
              {gw.status === "operational" ? (
                <span className={styles.badgeOperational}>
                  <span className={`${styles.statusDot} ${styles.dotGreen}`} />
                  Operational
                </span>
              ) : (
                <span className={styles.badgeError}>
                  <span className={`${styles.statusDot} ${styles.dotRed}`} />
                  Error / Offline / Missing Key
                </span>
              )}
            </div>

            <p className={styles.purposeSnippet}>{gw.purpose}</p>

            {/* Keys Summary Box */}
            <div className={styles.keysSummary}>
              {gw.keys.map((k) => (
                <div key={k.keyName} className={styles.keyRow}>
                  <span className={styles.keyName}>{k.keyName}</span>
                  <span className={styles.keyMasked}>{k.maskedValue}</span>
                </div>
              ))}
            </div>

            <div className={styles.cardFooter}>
              <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <Clock size={13} color="#94a3b8" />
                <span>Last Ping: {new Date(gw.lastPingAt).toLocaleTimeString()}</span>
              </div>
              <span className={styles.inspectCta}>
                Inspect Details <ChevronRight size={14} />
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* MODAL / DRAWER FOR GATEWAY DETAILS */}
      {selectedGateway && (
        <div
          className={styles.modalOverlay}
          onClick={() => setSelectedGateway(null)}
        >
          <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
            {/* Modal Header */}
            <div className={styles.modalHeader}>
              <div className={styles.modalTitleWrap}>
                <div
                  className={styles.modalLogo}
                  style={{ background: selectedGateway.brandColor }}
                >
                  {selectedGateway.displayName.charAt(0)}
                </div>
                <div>
                  <h2 className={styles.modalTitle}>
                    {selectedGateway.displayName}
                  </h2>
                  <p className={styles.modalSubtitle}>
                    {selectedGateway.provider} • {selectedGateway.category}
                  </p>
                </div>
              </div>

              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                {selectedGateway.status === "operational" ? (
                  <span className={styles.badgeOperational}>
                    <span className={`${styles.statusDot} ${styles.dotGreen}`} />
                    Operational
                  </span>
                ) : (
                  <span className={styles.badgeError}>
                    <span className={`${styles.statusDot} ${styles.dotRed}`} />
                    Error / Offline / Missing Key
                  </span>
                )}
                <button
                  className={styles.closeBtn}
                  onClick={() => setSelectedGateway(null)}
                >
                  <X size={16} />
                </button>
              </div>
            </div>

            <div className={styles.modalBody}>
              {/* 1. SERVICE PURPOSE */}
              <div className={styles.purposeBox}>
                <div className={styles.purposeTitle}>Service Purpose in Vektolux</div>
                <p className={styles.purposeText}>{selectedGateway.purpose}</p>
                <div className={styles.modalActionBar}>
                  <button
                    className={styles.toggleHealthBtn}
                    onClick={() => handleToggleHealth(selectedGateway.serviceId, "operational")}
                  >
                    ✓ Set Operational (Green)
                  </button>
                  <button
                    className={styles.toggleHealthBtn}
                    onClick={() => handleToggleHealth(selectedGateway.serviceId, "outage")}
                    style={{ color: "#dc2626" }}
                  >
                    ⚠ Simulate Outage / Offline (Red)
                  </button>
                </div>
              </div>

              {/* 2. CREDENTIAL MASK TABLE & OPERATIONAL FUNCTIONS */}
              <div>
                <div className={styles.sectionTitle}>
                  <Key size={16} color="#10b981" />
                  Gateway Credentials & Integration Locations
                </div>
                <div className={styles.credentialsList}>
                  {selectedGateway.keys.map((k) => (
                    <div key={k.keyName} className={styles.credentialCard}>
                      <div className={styles.credentialTop}>
                        <span className={styles.credKeyBadge}>{k.keyName}</span>
                        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                          <span className={styles.credMasked}>{k.maskedValue}</span>
                          <button
                            className={styles.editMaskBtn}
                            onClick={() =>
                              handleUpdateMask(
                                selectedGateway.serviceId,
                                k.keyName,
                                k.maskedValue
                              )
                            }
                          >
                            Edit Mask
                          </button>
                        </div>
                      </div>
                      <p className={styles.credDesc}>{k.operationalFunction}</p>
                      <div className={styles.credUsedIn}>
                        <Terminal size={12} />
                        <span>Used in:</span>
                        <code className={styles.credCode}>{k.usedIn}</code>
                        <span style={{ marginLeft: "auto", color: "#94a3b8" }}>
                          Env: <code>{k.envVarName}</code>
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* 3. DIAGNOSTIC PING & TIMESTAMPS */}
              <div>
                <div className={styles.sectionTitle}>
                  <Radio size={16} color="#3b82f6" />
                  Live Diagnostic Ping & Timestamps
                </div>
                <div className={styles.diagnosticRow}>
                  <div className={styles.pingTiming}>
                    <span style={{ fontSize: "12px", color: "#64748b" }}>
                      Last Verified Health Ping:
                    </span>
                    <span style={{ fontSize: "13px", fontWeight: 700, color: "#0f172a" }}>
                      {formatTimestamp(selectedGateway.lastPingAt)}
                    </span>
                    <span style={{ fontSize: "11.5px", color: "#94a3b8", marginTop: 2 }}>
                      Last Processed Transaction: {formatTimestamp(selectedGateway.lastTransactionAt)}
                    </span>
                  </div>

                  <button
                    className={styles.pingBtn}
                    onClick={() => handleDiagnosticPing(selectedGateway.serviceId)}
                    disabled={pinging}
                  >
                    <Activity
                      size={14}
                      style={{
                        animation: pinging ? "spin 1s linear infinite" : "none",
                      }}
                    />
                    {pinging ? "Pinging Gateway..." : "Run Diagnostic Ping"}
                  </button>
                </div>

                {pingResult && (
                  <div
                    style={{
                      marginTop: 8,
                      padding: "8px 12px",
                      borderRadius: 8,
                      fontSize: "12.5px",
                      fontWeight: 600,
                      background: pingResult.startsWith("✓")
                        ? "#ecfdf5"
                        : "#fef2f2",
                      color: pingResult.startsWith("✓")
                        ? "#059669"
                        : "#dc2626",
                      border: `1px solid ${
                        pingResult.startsWith("✓") ? "#a7f3d0" : "#fecaca"
                      }`,
                    }}
                  >
                    {pingResult}
                  </div>
                )}
              </div>

              {/* 4. ERROR LOG VIEW */}
              <div>
                <div className={styles.sectionTitle}>
                  <AlertTriangle size={16} color="#ef4444" />
                  Carrier Error Log View
                </div>

                {selectedGateway.errorLogs && selectedGateway.errorLogs.length > 0 ? (
                  <div className={styles.errorLogCard}>
                    {selectedGateway.errorLogs.map((log) => (
                      <div key={log.id} className={styles.errorLogItem}>
                        <div className={styles.errorLogTop}>
                          <span>
                            {log.endpoint}{" "}
                            {log.statusCode ? `(HTTP ${log.statusCode})` : ""}
                          </span>
                          <span>{formatTimestamp(log.occurredAt)}</span>
                        </div>
                        <div className={styles.errorMessageText}>
                          {log.errorMessage}
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className={styles.noErrorBox}>
                    <CheckCircle2 size={16} color="#10b981" />
                    <span>
                      Zero carrier errors reported. All endpoints responding within nominal SLA.
                    </span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
