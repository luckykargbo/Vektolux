/// <reference types="vite/client" />
// Upload security: budgeted upload URLs, public-media-only file URLs, validated and private identity documents.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { isAcceptableContentType, isListingVideoContentType, isPublicMediaContentType, MAX_UPLOAD_BYTES } from "./lib/uploads";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, role = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327200${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  return { id, token };
}
const store = (t: T, content: string, type = "image/jpeg") => t.run(async (ctx) => ctx.storage.store(new Blob([content], { type })));

describe("generateUploadUrl", () => {
  test("works for anonymous registration uploads and for signed-in users", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    expect(await t.mutation(api.files.generateUploadUrl, {})).toBeTypeOf("string");
    expect(await t.mutation(api.files.generateUploadUrl, { sessionToken: u.token })).toBeTypeOf("string");
  });

  test("a signed-in user is limited to 60 URLs per hour", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    for (let i = 0; i < 60; i++) await t.mutation(api.files.generateUploadUrl, { sessionToken: u.token });
    await expect(t.mutation(api.files.generateUploadUrl, { sessionToken: u.token })).rejects.toThrow(/limit/i);
    // another user is unaffected
    const v = await makeUser(t, "v");
    await expect(t.mutation(api.files.generateUploadUrl, { sessionToken: v.token })).resolves.toBeTypeOf("string");
  });
});

describe("content types", () => {
  test("images and PDF pass; HTML, SVG, scripts and executables are refused", () => {
    for (const ok of ["image/jpeg", "image/PNG", "image/webp", "image/heic", "application/pdf", "image/jpeg; charset=binary", undefined, ""]) {
      expect(isAcceptableContentType(ok as any)).toBe(true);
    }
    for (const bad of ["text/html", "image/svg+xml", "application/javascript", "application/x-msdownload", "application/octet-stream", "text/plain"]) {
      expect(isAcceptableContentType(bad)).toBe(false);
    }
  });

  test("property videos: phone formats are public media; pages, scripts and unknown types are not", () => {
    for (const ok of ["video/mp4", "VIDEO/MP4", "video/quicktime", "video/webm", "video/3gpp", "video/mp4; codecs=avc1"]) {
      expect(isListingVideoContentType(ok)).toBe(true);
      expect(isPublicMediaContentType(ok)).toBe(true);
    }
    for (const bad of ["text/html", "video/html", "image/svg+xml", "application/octet-stream", "image/jpeg", undefined, ""]) {
      expect(isListingVideoContentType(bad as any)).toBe(false);
    }
    expect(isPublicMediaContentType("text/html")).toBe(false);
    expect(isPublicMediaContentType("image/svg+xml")).toBe(false);
    expect(isPublicMediaContentType("image/png")).toBe(true);
    // Videos are NOT accepted where only images/PDF may be attached (identity documents, avatars).
    expect(isAcceptableContentType("video/mp4")).toBe(false);
  });
});

describe("getFileUrl", () => {
  test("serves public media, refuses unknown ids and private identity files", async () => {
    const t = convexTest(schema, modules);
    const img = await store(t, "x", "image/png");
    expect(await t.query(api.files.getFileUrl, { storageId: img as string })).toBeTypeOf("string");
    expect(await t.query(api.files.getFileUrl, { storageId: "not-a-real-id" })).toBeNull();
    await t.run(async (ctx) => ctx.db.insert("private_files", { storageId: img as string, kind: "identity_document", createdAt: Date.now() }));
    expect(await t.query(api.files.getFileUrl, { storageId: img as string })).toBeNull();
  });

  test("serves an uploaded property video (the agent's preview plays the stored file)", async () => {
    const t = convexTest(schema, modules);
    const vid = await store(t, "vid", "video/mp4");
    expect(await t.query(api.files.getFileUrl, { storageId: vid as string })).toBeTypeOf("string");
  });
});

describe("identity documents", () => {
  test("an oversized upload is rejected and deleted; a real one is stored private", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    const huge = await store(t, "x".repeat(MAX_UPLOAD_BYTES + 1));
    const good = await store(t, "img");
    const selfie = await store(t, "img");
    const args = (idPhoto: Id<"_storage">) => ({
      userId: u.id as string, sessionToken: u.token, accountType: "INDIVIDUAL" as any, idType: "NATIONAL_ID" as any, idNumber: "SL-1",
      idPhotoStorageId: idPhoto, selfieStorageId: selfie, livenessPassed: true, faceMatchPassed: true,
    });
    const rejected: any = await t.mutation(api.businessVerification.submitTieredVerification, args(huge));
    expect(rejected.success).toBe(false);
    expect(rejected.errorMessage).toMatch(/too large/);
    expect(await t.run(async (ctx) => ctx.db.system.get(huge))).toBeNull();

    const ok: any = await t.mutation(api.businessVerification.submitTieredVerification, args(good));
    expect(ok.status).toBe("PENDING_REVIEW");
    expect(await t.query(api.files.getFileUrl, { storageId: good as string })).toBeNull();
    expect(await t.query(api.files.getFileUrl, { storageId: selfie as string })).toBeNull();
  });

  test("registration: an oversized document is refused (no account); a valid one gets a server-derived URL", async () => {
    const t = convexTest(schema, modules);
    const base = { name: "Reg User", phone: "+23279000111", password: "longpassword1", role: "client" };
    const huge = await store(t, "x".repeat(MAX_UPLOAD_BYTES + 1));
    const refused: any = await t.mutation(api.auth.registerUser, { ...base, email: "reg1@t.vx", documentStorageId: huge });
    expect(refused.success).toBe(false);
    expect(await t.run(async (ctx) => ctx.db.query("users").collect())).toHaveLength(0);

    const good = await store(t, "img");
    const ok: any = await t.mutation(api.auth.registerUser, {
      ...base, phone: "+23279000222", email: "reg2@t.vx", role: "Real Estate Agent", documentStorageId: good, documentUrl: "https://evil.example/phish",
    });
    expect(ok.success).toBe(true);
    const user = await t.run(async (ctx) => ctx.db.get(ok.userId as Id<"users">));
    expect(user?.documentUrl).toBeTypeOf("string");
    expect(user?.documentUrl).not.toContain("evil.example");
    const apps = await t.run(async (ctx) => ctx.db.query("role_applications").collect());
    expect(JSON.stringify(apps)).not.toContain("evil.example");
    expect(await t.query(api.files.getFileUrl, { storageId: good as string })).toBeNull();
  });
});
