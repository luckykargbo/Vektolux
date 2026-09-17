"use client";
// src/app/dashboard/layout.tsx — Shared dashboard shell with sidebar nav
import { LayoutDashboard, Users, FileCheck, FolderOpen, Zap, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import type { AdminSession } from "@/lib/types";
import styles from "./dashboard.module.css";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [session, setSession] = useState<AdminSession | null>(null);

  useEffect(() => {
    const raw = sessionStorage.getItem("adminSession");
    if (!raw) {
      router.push("/");
      return;
    }
    try {
      setSession(JSON.parse(raw));
    } catch {
      router.push("/");
    }
  }, [router]);

  function handleLogout() {
    sessionStorage.removeItem("adminSession");
    router.push("/");
  }

  if (!session) {
    return (
      <div className={styles.loading}>
        <div className={styles.spinner} />
        <p>Verifying session…</p>
      </div>
    );
  }

  const navLinks = [
    { href: "/dashboard", label: "Overview", icon: <LayoutDashboard size={18} /> },
    { href: "/dashboard/escrow", label: "Escrow & Settlements", icon: <ShieldCheck size={18} /> },
    { href: "/dashboard/users", label: "User Directory", icon: <Users size={18} /> },
    { href: "/dashboard/verifications", label: "Verification Queue", icon: <FileCheck size={18} /> },
    { href: "/dashboard/listings", label: "Listings Inspector", icon: <FolderOpen size={18} /> },
    { href: "/dashboard/seed", label: "Quick Seed", icon: <Zap size={18} /> },
  ];

  return (
    <div className={styles.shell}>
      {/* Sidebar */}
      <aside className={styles.sidebar}>
        <div className={styles.sidebarHeader}>
          <span className={styles.sidebarLogo}><Zap size={24} /></span>
          <div>
            <div className={styles.sidebarBrand}>Vektolux</div>
            <div className={styles.sidebarRole}>Admin Dashboard</div>
          </div>
        </div>

        <nav className={styles.nav}>
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className={`${styles.navLink} ${pathname === link.href ? styles.navLinkActive : ""}`}
            >
              <span className={styles.navIcon}>{link.icon}</span>
              {link.label}
            </a>
          ))}
        </nav>

        <div className={styles.sidebarFooter}>
          <div className={styles.adminInfo}>
            <div className={styles.adminAvatar}>
              {session.user.name.charAt(0).toUpperCase()}
            </div>
            <div>
              <div className={styles.adminName}>{session.user.name}</div>
              <div className={styles.adminEmail}>{session.user.email}</div>
            </div>
          </div>
          <button onClick={handleLogout} className={styles.logoutBtn}>
            Sign Out
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className={styles.content}>{children}</main>
    </div>
  );
}
