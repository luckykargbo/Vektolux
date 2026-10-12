"use client";
// src/app/page.tsx — Vektolux Admin Login with Founder Showcase Background
import { useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import styles from "./login.module.css";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [totpCode, setTotpCode] = useState("");
  const [mfaRequired, setMfaRequired] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, totpCode: mfaRequired ? totpCode : undefined }),
      });

      const data = await res.json();

      if (data.mfaRequired) {
        setMfaRequired(true);
        setLoading(false);
        return;
      }

      if (!res.ok || !data.success) {
        setError(data.error ?? "Invalid email or password.");
        setLoading(false);
        return;
      }

      // Store non-sensitive user metadata for layout UI display
      if (data.session) {
        sessionStorage.setItem("adminSession", JSON.stringify(data.session));
      }

      const fromParam = typeof window !== "undefined"
        ? new URLSearchParams(window.location.search).get("from")
        : null;
      const destination = fromParam && fromParam.startsWith("/dashboard") ? fromParam : "/dashboard";
      router.push(destination);
    } catch (err) {
      setError("Network error — please check your connection.");
      setLoading(false);
    }
  }

  function handleBackToCredentials() {
    setMfaRequired(false);
    setPassword("");
    setTotpCode("");
    setError("");
  }

  return (
    <main className={styles.main}>
      {/* Dark Translucent Backdrop Overlay with Blur */}
      <div className={styles.overlay} />

      {/* Centered Glassmorphic Login Card */}
      <div className={styles.card}>
        {/* Header with Official Vektolux Logo */}
        <div className={styles.header}>
          <div className={styles.logoWrap}>
            <img
              src="/images/vektolux-logo.png"
              alt="Vektolux Logo"
              className={styles.logoImg}
            />
          </div>
          <h1 className={styles.title}>Vektolux Admin</h1>
          <p className={styles.subtitle}>Super App Management Console</p>
        </div>

        {/* Connection Status Badge */}
        <div className={styles.badge}>
          <span className={styles.badgeDot} />
          Connected to Production Convex
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className={styles.form}>
          {!mfaRequired ? (
            <>
              <div className={styles.field}>
                <label htmlFor="email" className={styles.label}>Admin Email</label>
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className={styles.input}
                  placeholder="admin@vektolux.sl"
                  required
                  autoComplete="username"
                />
              </div>

              <div className={styles.field}>
                <label htmlFor="password" className={styles.label}>Password</label>
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className={styles.input}
                  placeholder="Enter admin password"
                  required
                  autoComplete="current-password"
                />
              </div>
            </>
          ) : (
            <div className={styles.field}>
              <label htmlFor="totpCode" className={styles.label}>Two-Factor Authentication Code</label>
              <input
                id="totpCode"
                type="text"
                value={totpCode}
                onChange={(e) => setTotpCode(e.target.value)}
                className={styles.input}
                placeholder="6-digit code or backup code"
                required
                autoFocus
                autoComplete="one-time-code"
              />
              <p style={{ fontSize: "12px", color: "rgba(255,255,255,0.6)", marginTop: "6px" }}>
                Enter the 6-digit verification code from your authenticator app or an 8-character emergency backup code.
              </p>
            </div>
          )}

          {error && (
            <div className={styles.error}>
              <span>⚠️</span> {error}
            </div>
          )}

          <button type="submit" className={styles.btn} disabled={loading}>
            {loading ? "Authenticating…" : mfaRequired ? "Verify & Sign In" : "Sign In to Dashboard"}
          </button>

          {mfaRequired && (
            <button
              type="button"
              onClick={handleBackToCredentials}
              style={{
                background: "transparent",
                border: "none",
                color: "rgba(255,255,255,0.7)",
                cursor: "pointer",
                fontSize: "13px",
                marginTop: "10px",
                textAlign: "center",
                width: "100%",
              }}
            >
              ← Back to credentials
            </button>
          )}
        </form>

        <p className={styles.hint}>
          This console runs locally and securely connects to the live Convex database.
          Access is strictly restricted to authorized Vektolux administrators.
        </p>
      </div>
    </main>
  );
}
