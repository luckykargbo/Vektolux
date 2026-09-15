// src/lib/convex.ts
// Convex client singleton for the admin dashboard
import { ConvexHttpClient } from "convex/browser";

const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL ?? "https://incredible-possum-462.convex.cloud";

// HTTP client for server-side calls (API routes)
export const convexHttpClient = new ConvexHttpClient(CONVEX_URL);

export { CONVEX_URL };
