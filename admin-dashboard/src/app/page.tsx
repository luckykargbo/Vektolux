"use client";
// src/app/page.tsx — Vektolux Admin Login with Founder Showcase Background
import { useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import styles from "./login.module.css";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("admin@vektolux.sl");
  const [password, setPassword] = useState("");
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
        body: JSON.stringify({ email, password }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        setError(data.error ?? "Login failed. Check your credentials.");
        setLoading(false);
        return;
      }

      // Store session in sessionStorage (local only — clears on browser close)
      sessionStorage.setItem("adminSession", JSON.stringify(data.session));
      router.push("/dashboard");
    } catch (err) {
      setError("Network error — is the server running?");
      setLoading(false);
    }
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

          {error && (
            <div className={styles.error}>
              <span>⚠️</span> {error}
            </div>
          )}

          <button type="submit" className={styles.btn} disabled={loading}>
            {loading ? "Authenticating…" : "Sign In to Dashboard"}
          </button>
        </form>

        <p className={styles.hint}>
          This console runs locally and securely connects to the live Convex database.
          Access is strictly restricted to authorized Vektolux administrators.
        </p>
      </div>
    </main>
  );
}
