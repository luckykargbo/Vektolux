// src/lib/convex.ts
// Convex client singleton for the admin dashboard
import { ConvexHttpClient } from "convex/browser";
import dns from "node:dns";

try {
  dns.setDefaultResultOrder("ipv4first");
} catch (_) {}

const CONVEX_URL =
  process.env.NEXT_PUBLIC_CONVEX_URL ||
  process.env.CONVEX_URL ||
  "https://ideal-poodle-813.convex.cloud";

// HTTP client for server-side calls (API routes)
export const convexHttpClient = new ConvexHttpClient(CONVEX_URL);

export { CONVEX_URL };
