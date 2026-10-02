// convex/files.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Convex File & Media Storage Handlers
//
//  • generateUploadUrl: budgeted. A signed-in user gets 60 upload URLs per hour. Registration
//    uploads happen BEFORE an account exists, so anonymous callers share a separate global budget
//    (Convex exposes no client IP, so per-IP limits need an edge/WAF in front of the deployment).
//    Type and size are validated when the file is attached to a record (lib/uploads.ts).
//  • getFileUrl: public media only (images/PDF). Files attached to identity verification are
//    private and never served here; admins use businessVerification.getSignedDocumentUrl.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { resolveOptionalUser } from "./lib/auth";
import { consume } from "./lib/rateLimit";
import { isAcceptableContentType, isPrivateFile } from "./lib/uploads";

const HOUR = 60 * 60 * 1000;
const USER_UPLOADS_PER_HOUR = 60;
const ANON_UPLOADS_PER_HOUR = 300;

/** Short-lived signed upload URL for Convex Storage. */
export const generateUploadUrl = mutation({
  args: { sessionToken: v.optional(v.string()) },
  returns: v.string(),
  handler: async (ctx, args) => {
    const user = await resolveOptionalUser(ctx, { sessionToken: args.sessionToken });
    const allowed = user
      ? await consume(ctx, `upload:user:${user.userId}`, { max: USER_UPLOADS_PER_HOUR, windowMs: HOUR })
      : await consume(ctx, "upload:anonymous", { max: ANON_UPLOADS_PER_HOUR, windowMs: HOUR });
    if (!allowed) {
      throw new Error("Upload limit reached. Please try again later.");
    }
    return await ctx.storage.generateUploadUrl();
  },
});

/** The URL of a PUBLIC media file (listing photo, avatar). Private/identity files and non-media return null. */
export const getFileUrl = query({
  args: {
    storageId: v.string(),
  },
  returns: v.union(v.string(), v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.system.normalizeId("_storage", args.storageId);
    if (!id) return null;
    const meta = await ctx.db.system.get(id);
    if (!meta || !isAcceptableContentType(meta.contentType)) return null; // public media only
    if (await isPrivateFile(ctx, args.storageId)) return null;
    return await ctx.storage.getUrl(id);
  },
});
