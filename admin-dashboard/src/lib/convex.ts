// src/lib/convex.ts
// Convex client singleton for the admin dashboard
import { ConvexHttpClient } from "convex/browser";
import dns from "node:dns";

try {
  dns.setDefaultResultOrder("ipv4first");
} catch (_) {}

const CONVEX_URL = (
  process.env.CONVEX_URL ||
  process.env.NEXT_PUBLIC_CONVEX_URL ||
  ""
).trim();

if (!CONVEX_URL && typeof process !== "undefined" && process.env.NODE_ENV === "production") {
  console.error(
    "[FATAL] CONVEX_URL or NEXT_PUBLIC_CONVEX_URL environment variable is not configured."
  );
}

// HTTP client for server-side calls (API routes)
export const convexHttpClient = new ConvexHttpClient(
  CONVEX_URL || "https://unconfigured-deployment.convex.cloud"
);

export function requireConvexUrl(): string {
  if (!CONVEX_URL) {
    throw new Error(
      "Missing CONVEX_URL environment variable. Please configure it in your environment."
    );
  }
  return CONVEX_URL;
}

export { CONVEX_URL };

