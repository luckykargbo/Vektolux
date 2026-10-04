// convex/messaging.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Two-way conversations between a buyer and a listing's seller.
//
// Built on the existing in-app contact relay (contact_requests): a buyer's inquiry about a
// listing opens a conversation; both participants can then reply here. Only the two
// participants can read or write a thread. Nothing private is returned: no phone number,
// email or exact address — only names, avatars and the listing's public summary.
//  • A declined inquiry closes its conversation.
//  • Messages: 1–2000 characters, at most 20 per minute per sender.
//  • Unread counters are denormalised on the request (no row counting); one notification is
//    sent per burst of unread messages, not one per message.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { requireSelf } from "./lib/auth";
import { publicLocation } from "./lib/slLocations";

export const MAX_MESSAGE_LENGTH = 2000;
export const MAX_MESSAGES_PER_MINUTE = 20;
const PREVIEW = 140;
const THREAD_LIMIT = 200;

type Role = "buyer" | "seller";

async function loadThread(ctx: { db: any; auth: any }, sessionToken: string | undefined, requestId: string) {
  const { userId, user } = await requireSelf(ctx, sessionToken);
  const id = ctx.db.normalizeId("contact_requests", requestId);
  const req: Doc<"contact_requests"> | null = id ? await ctx.db.get(id) : null;
  // Same answer for "missing" and "not yours": a thread's existence is not revealed.
  if (!req) throw new Error("Conversation not found.");
  let role: Role;
  if (req.buyerId === userId) role = "buyer";
  else if (req.sellerId === userId) role = "seller";
  else throw new Error("Conversation not found.");
  return { userId: userId as Id<"users">, user: user as Doc<"users">, req, role };
}

/** Public summary of the listing a conversation is about (never the private address/phone). */
async function listingSummary(ctx: { db: any }, req: Doc<"contact_requests">) {
  const firstImage = (urls: unknown) =>
    Array.isArray(urls) ? (urls.find((u) => typeof u === "string" && /^https?:\/\//.test(u)) ?? null) : null;
  if (req.listingType === "property") {
    const id = ctx.db.normalizeId("realEstateListings", req.listingId);
    const p = id ? await ctx.db.get(id) : null;
    if (!p || p.isDeleted === true) return null;
    return {
      id: p._id as string,
      type: "property" as const,
      title: p.title as string,
      category: p.category as string,
      price: p.price as number,
      hourlyRate: (p.hourlyRate ?? null) as number | null,
      currency: (p.currency ?? "SLE") as string,
      imageUrl: firstImage(p.imageUrls) as string | null,
      location: publicLocation(p.city, p.district),
    };
  }
  const id = ctx.db.normalizeId("vehicleListings", req.listingId);
  const veh = id ? await ctx.db.get(id) : null;
  if (!veh || veh.isDeleted === true) return null;
  return {
    id: veh._id as string,
    type: "vehicle" as const,
    title: veh.title as string,
    category: veh.category as string,
    price: veh.price as number,
    hourlyRate: null,
    currency: (veh.currency ?? "SLE") as string,
    imageUrl: firstImage(veh.images ?? veh.imageUrls) as string | null,
    location: publicLocation(veh.location, veh.district),
  };
}

function person(u: Doc<"users"> | null) {
  return u
    ? { id: u._id as string, name: u.name, avatarUrl: u.avatarUrl ?? null, isVerified: u.isVerified === true }
    : { id: "", name: "Vektolux user", avatarUrl: null, isVerified: false };
}

function unreadFor(req: Doc<"contact_requests">, role: Role): number {
  if (role === "buyer") return req.buyerUnread ?? 0;
  // Requests from before messaging have no counter: an unanswered one counts as unread.
  return req.sellerUnread ?? (req.status === "pending" && req.lastMessageAt === undefined ? 1 : 0);
}

async function conversationView(ctx: { db: any }, req: Doc<"contact_requests">, role: Role) {
  const myId = role === "buyer" ? req.buyerId : req.sellerId;
  const counterpart = await ctx.db.get(role === "buyer" ? req.sellerId : req.buyerId);
  return {
    id: req._id as string,
    myRole: role,
    status: req.status,
    counterpart: person(counterpart),
    listingId: req.listingId,
    listingType: req.listingType,
    listing: await listingSummary(ctx, req),
    lastMessage: req.lastMessagePreview ?? req.message.slice(0, PREVIEW),
    lastMessageAt: req.lastMessageAt ?? req.createdAt,
    lastMessageFromMe: req.lastSenderId ? req.lastSenderId === myId : role === "buyer",
    unread: unreadFor(req, role),
    createdAt: req.createdAt,
  };
}

/** The caller's conversations (as seller, as buyer, or both), most recent activity first. */
export const getMyConversations = query({
  args: {
    sessionToken: v.optional(v.string()),
    role: v.optional(v.union(v.literal("buyer"), v.literal("seller"))),
  },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const asSeller =
      args.role === "buyer"
        ? []
        : await ctx.db.query("contact_requests").withIndex("by_sellerId", (q) => q.eq("sellerId", userId)).order("desc").take(100);
    const asBuyer =
      args.role === "seller"
        ? []
        : await ctx.db.query("contact_requests").withIndex("by_buyerId", (q) => q.eq("buyerId", userId)).order("desc").take(100);
    const out = [];
    for (const req of asSeller) out.push(await conversationView(ctx, req, "seller"));
    for (const req of asBuyer) out.push(await conversationView(ctx, req, "buyer"));
    out.sort((a, b) => b.lastMessageAt - a.lastMessageAt);
    return out;
  },
});

/** One conversation with its messages (participants only), oldest first. */
export const getThread = query({
  args: { sessionToken: v.optional(v.string()), requestId: v.string() },
  handler: async (ctx, args) => {
    const { req, role } = await loadThread(ctx, args.sessionToken, args.requestId);
    const myId = role === "buyer" ? req.buyerId : req.sellerId;
    const rows = await ctx.db
      .query("contact_messages")
      .withIndex("by_requestId_and_createdAt", (q) => q.eq("requestId", req._id))
      .order("desc")
      .take(THREAD_LIMIT);
    rows.reverse();
    return {
      conversation: await conversationView(ctx, req, role),
      canSend: req.status !== "declined",
      truncated: rows.length === THREAD_LIMIT,
      messages: [
        // The inquiry that opened the conversation (always the buyer's).
        { id: `${req._id}:inquiry`, fromMe: role === "buyer", body: req.message, createdAt: req.createdAt, readAt: null as number | null },
        ...rows.map((m) => ({
          id: m._id as string,
          fromMe: m.senderId === myId,
          body: m.body,
          createdAt: m.createdAt,
          readAt: m.readAt ?? null,
        })),
      ],
    };
  },
});

/** Sends a reply in a conversation the caller takes part in. */
export const sendMessage = mutation({
  args: { sessionToken: v.optional(v.string()), requestId: v.string(), body: v.string() },
  handler: async (ctx, args) => {
    const { userId, user, req, role } = await loadThread(ctx, args.sessionToken, args.requestId);
    if (req.status === "declined") throw new Error("This conversation is closed.");
    const body = args.body.trim();
    if (!body) throw new Error("Write a message first.");
    if (body.length > MAX_MESSAGE_LENGTH) throw new Error(`Messages can be at most ${MAX_MESSAGE_LENGTH} characters.`);
    const now = Date.now();
    const recent = await ctx.db
      .query("contact_messages")
      .withIndex("by_senderId_and_createdAt", (q) => q.eq("senderId", userId).gt("createdAt", now - 60_000))
      .take(MAX_MESSAGES_PER_MINUTE);
    if (recent.length >= MAX_MESSAGES_PER_MINUTE) throw new Error("You are sending messages too quickly. Please wait a moment.");

    const id = await ctx.db.insert("contact_messages", { requestId: req._id, senderId: userId, body, createdAt: now });
    const recipientId = role === "buyer" ? req.sellerId : req.buyerId;
    const recipientUnread = role === "buyer" ? (req.sellerUnread ?? 0) : (req.buyerUnread ?? 0);
    await ctx.db.patch(req._id, {
      lastMessageAt: now,
      lastMessagePreview: body.slice(0, PREVIEW),
      lastSenderId: userId,
      ...(role === "buyer" ? { sellerUnread: recipientUnread + 1 } : { buyerUnread: recipientUnread + 1 }),
    });
    // One notification per burst: only when the recipient had nothing unread in this thread.
    if (recipientUnread === 0) {
      await ctx.db.insert("user_notifications", {
        userId: recipientId as string,
        targetType: "single_user",
        title: `New message from ${user.name}`,
        body: body.slice(0, PREVIEW),
        deepLinkScreen: "messages",
        deepLinkId: req._id as string,
        read: false,
        createdAt: now,
      });
    }
    return { id: id as string, createdAt: now };
  },
});

/** Marks the other participant's messages in a conversation as read. */
export const markThreadRead = mutation({
  args: { sessionToken: v.optional(v.string()), requestId: v.string() },
  handler: async (ctx, args) => {
    const { userId, req, role } = await loadThread(ctx, args.sessionToken, args.requestId);
    const now = Date.now();
    const rows = await ctx.db
      .query("contact_messages")
      .withIndex("by_requestId_and_createdAt", (q) => q.eq("requestId", req._id))
      .order("desc")
      .take(THREAD_LIMIT);
    for (const m of rows) {
      if (m.senderId !== userId && m.readAt === undefined) await ctx.db.patch(m._id, { readAt: now });
    }
    await ctx.db.patch(req._id, role === "buyer" ? { buyerUnread: 0 } : { sellerUnread: 0 });
    return true;
  },
});
