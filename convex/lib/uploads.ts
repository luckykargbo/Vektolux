// convex/lib/uploads.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Upload validation and privacy marking for Convex file storage.
//
// Convex cannot restrict type/size at upload time, so every server function that ATTACHES a file
// to a record validates its stored metadata here and deletes anything that is not an image or PDF
// within the size limit. Files attached to identity verification are marked PRIVATE: they are never
// served by the public `files:getFileUrl` (admins fetch them through an admin-only function).
// ═══════════════════════════════════════════════════════════════════════

import type { Id } from "../_generated/dataModel";

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10 MB

export type UploadCheck = { ok: true } | { ok: false; reason: string };

/** Types the app uploads. SVG is deliberately NOT allowed (it can carry script). */
const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/gif",
  "image/webp",
  "image/heic",
  "image/heif",
  "image/avif",
  "application/pdf",
]);

/**
 * Convex serves a file with the Content-Type it was uploaded with, so an uploaded HTML/SVG file
 * would otherwise run script from the deployment's own domain. A file with NO stored type is served
 * as a plain download (never rendered), so it is not a script risk and is tolerated.
 */
export function isAcceptableContentType(contentType: string | undefined | null): boolean {
  if (contentType === undefined || contentType === null || contentType === "") return true;
  return ALLOWED_TYPES.has(contentType.toLowerCase().split(";")[0].trim());
}

/** Property video types. Browsers play these as media; none of them can render as a page. */
const LISTING_VIDEO_TYPES = new Set([
  "video/mp4",
  "video/quicktime",
  "video/webm",
  "video/3gpp",
  "video/3gpp2",
  "video/x-m4v",
  "video/mpeg",
]);

export function isListingVideoContentType(contentType: string | undefined | null): boolean {
  if (!contentType) return false;
  return LISTING_VIDEO_TYPES.has(contentType.toLowerCase().split(";")[0].trim());
}

/** What the public `files:getFileUrl` may serve: images, PDFs and property videos. */
export function isPublicMediaContentType(contentType: string | undefined | null): boolean {
  return isAcceptableContentType(contentType) || isListingVideoContentType(contentType);
}

/** Validates a stored file's type and size; deletes it if it is not acceptable. */
export async function validateUpload(
  ctx: { db: any; storage: any },
  storageId: Id<"_storage">
): Promise<UploadCheck> {
  const meta = await ctx.db.system.get(storageId);
  if (!meta) return { ok: false, reason: "The uploaded file was not found." };
  if (!isAcceptableContentType(meta.contentType)) {
    await ctx.storage.delete(storageId);
    return { ok: false, reason: "Only images and PDF documents are accepted." };
  }
  if (typeof meta.size === "number" && meta.size > MAX_UPLOAD_BYTES) {
    await ctx.storage.delete(storageId);
    return { ok: false, reason: "The file is too large (maximum 10 MB)." };
  }
  return { ok: true };
}

/** Marks a file as private (identity documents, selfies, ownership papers). Idempotent. */
export async function markPrivateFile(
  ctx: { db: any },
  storageId: Id<"_storage">,
  kind: string,
  ownerUserId?: Id<"users">
): Promise<void> {
  const existing = await ctx.db
    .query("private_files")
    .withIndex("by_storageId", (q: any) => q.eq("storageId", storageId))
    .first();
  if (existing) return;
  await ctx.db.insert("private_files", { storageId, kind, ownerUserId, createdAt: Date.now() });
}

export async function isPrivateFile(ctx: { db: any }, storageId: string): Promise<boolean> {
  const row = await ctx.db
    .query("private_files")
    .withIndex("by_storageId", (q: any) => q.eq("storageId", storageId))
    .first();
  return !!row;
}
