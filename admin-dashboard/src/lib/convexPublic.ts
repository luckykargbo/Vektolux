// src/lib/convexPublic.ts — Convex deployment URL for browser code (no Node-only imports).
// Read strictly from NEXT_PUBLIC_CONVEX_URL.
export const CONVEX_URL: string = (
  process.env.NEXT_PUBLIC_CONVEX_URL || ""
).trim();
