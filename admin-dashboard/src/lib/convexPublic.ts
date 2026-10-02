// src/lib/convexPublic.ts — Convex deployment URL for browser code (no Node-only imports).
// Always the configured deployment; there is no fallback to any other deployment.
export const CONVEX_URL: string =
  process.env.NEXT_PUBLIC_CONVEX_URL || "https://ideal-poodle-813.convex.cloud";
