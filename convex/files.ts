// convex/files.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Convex File & Media Storage Handlers
// Handles file upload URL generation and retrieval of public asset URLs.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Generate a short-lived signed upload URL for uploading files to Convex Storage.
 */
export const generateUploadUrl = mutation({
  args: {},
  returns: v.string(),
  handler: async (ctx) => {
    return await ctx.storage.generateUploadUrl();
  },
});

/**
 * Retrieve the publicly accessible URL for a given storage ID.
 */
export const getFileUrl = query({
  args: {
    storageId: v.string(),
  },
  returns: v.union(v.string(), v.null()),
  handler: async (ctx, args) => {
    return await ctx.storage.getUrl(args.storageId as any);
  },
});
