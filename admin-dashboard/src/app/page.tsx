"use client";
// src/app/page.tsx — Admin Login Page
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
      setError("Network error — is the app running?");
      setLoading(false);
    }
  }

  return (
    <main className={styles.main}>
      <div className={styles.card}>
        {/* Header */}
        <div className={styles.header}>
          <div className={styles.logo}>⚡</div>
          <h1 className={styles.title}>Vektolux Admin</h1>
          <p className={styles.subtitle}>Local Management Dashboard</p>
        </div>

        {/* Badge */}
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
          This dashboard runs locally and connects directly to the live Convex database.
          Only authorised Vektolux administrators should have access.
        </p>
      </div>
    </main>
  );
}
