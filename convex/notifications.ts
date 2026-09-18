// convex/notifications.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Push & In-App Notification System
// Handles device token registration, notification delivery logs,
// real-time unread count tracking, and deep-link metadata routing.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// ═══════════════════════════════════════════════════════════════════════
//                      DEVICE TOKEN MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════

/**
 * Registers or updates an FCM device token for an authenticated user.
 */
export const registerDeviceToken = mutation({
  args: {
    userId: v.string(),
    fcmToken: v.string(),
    deviceType: v.string(), // "android" | "ios" | "web"
    topics: v.optional(v.array(v.string())),
  },
  returns: v.object({
    success: v.boolean(),
    tokenId: v.string(),
  }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("user_fcm_tokens")
      .withIndex("by_token", (q) => q.eq("fcmToken", args.fcmToken))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        userId: args.userId,
        deviceType: args.deviceType,
        topics: args.topics ?? ["all_users"],
        lastUpdated: now,
      });
      return { success: true, tokenId: existing._id as string };
    }

    const tokenId = await ctx.db.insert("user_fcm_tokens", {
      userId: args.userId,
      fcmToken: args.fcmToken,
      deviceType: args.deviceType,
      topics: args.topics ?? ["all_users"],
      lastUpdated: now,
    });

    return { success: true, tokenId: tokenId as string };
  },
});

/**
 * Retrieves active device FCM tokens for a specific user.
 */
export const getUserTokens = query({
  args: {
    userId: v.string(),
  },
  returns: v.array(
    v.object({
      id: v.string(),
      fcmToken: v.string(),
      deviceType: v.string(),
      lastUpdated: v.number(),
    })
  ),
  handler: async (ctx, args) => {
    const tokens = await ctx.db
      .query("user_fcm_tokens")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    return tokens.map((t) => ({
      id: t._id as string,
      fcmToken: t.fcmToken,
      deviceType: t.deviceType,
      lastUpdated: t.lastUpdated,
    }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      IN-APP NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Fetches notifications relevant to a user (both direct and broadcast),
 * mapped with proper read status and ordered newest first.
 */
export const getUserNotifications = query({
  args: {
    userId: v.string(),
    limit: v.optional(v.number()),
  },
  returns: v.array(
    v.object({
      id: v.string(),
      targetType: v.string(),
      title: v.string(),
      body: v.string(),
      deepLinkScreen: v.optional(v.string()),
      deepLinkId: v.optional(v.string()),
      data: v.optional(v.string()),
      read: v.boolean(),
      createdAt: v.number(),
    })
  ),
  handler: async (ctx, args) => {
    const takeCount = args.limit ?? 30;

    // 1. Fetch targeted direct notifications
    const directNotifs = await ctx.db
      .query("user_notifications")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(takeCount);

    // 2. Fetch broadcast announcements
    const broadcastNotifs = await ctx.db
      .query("user_notifications")
      .withIndex("by_target_type", (q) => q.eq("targetType", "all_users"))
      .order("desc")
      .take(takeCount);

    // 3. Merge & Deduplicate
    const combined = [...directNotifs, ...broadcastNotifs];
    const seenIds = new Set<string>();
    const unique = combined.filter((n) => {
      const idStr = n._id as string;
      if (seenIds.has(idStr)) return false;
      seenIds.add(idStr);
      return true;
    });

    // 4. Sort descending by createdAt
    unique.sort((a, b) => b.createdAt - a.createdAt);

    // 5. Compute effective read state
    return unique.slice(0, takeCount).map((n) => {
      const isDirect = n.targetType === "single_user";
      const isRead = isDirect
        ? n.read
        : (n.readByUsers ?? []).includes(args.userId);

      return {
        id: n._id as string,
        targetType: n.targetType,
        title: n.title,
        body: n.body,
        deepLinkScreen: n.deepLinkScreen,
        deepLinkId: n.deepLinkId,
        data: n.data,
        read: isRead,
        createdAt: n.createdAt,
      };
    });
  },
});

/**
 * Returns the unread notification count for badge display.
 */
export const getUnreadNotificationCount = query({
  args: {
    userId: v.string(),
  },
  returns: v.number(),
  handler: async (ctx, args) => {
    // 1. Direct unread notifications
    const directNotifs = await ctx.db
      .query("user_notifications")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();
    const unreadDirect = directNotifs.filter((n) => !n.read).length;

    // 2. Broadcast unread notifications
    const broadcastNotifs = await ctx.db
      .query("user_notifications")
      .withIndex("by_target_type", (q) => q.eq("targetType", "all_users"))
      .take(50);
    const unreadBroadcast = broadcastNotifs.filter(
      (n) => !(n.readByUsers ?? []).includes(args.userId)
    ).length;

    return unreadDirect + unreadBroadcast;
  },
});

/**
 * Marks a notification as read.
 */
export const markAsRead = mutation({
  args: {
    notificationId: v.id("user_notifications"),
    userId: v.string(),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const notif = await ctx.db.get(args.notificationId);
    if (!notif) return false;

    if (notif.targetType === "single_user") {
      await ctx.db.patch(args.notificationId, { read: true });
    } else {
      const readList = notif.readByUsers ?? [];
      if (!readList.includes(args.userId)) {
        await ctx.db.patch(args.notificationId, {
          readByUsers: [...readList, args.userId],
        });
      }
    }
    return true;
  },
});

/**
 * Marks all notifications for a user as read.
 */
export const markAllAsRead = mutation({
  args: {
    userId: v.string(),
  },
  returns: v.number(),
  handler: async (ctx, args) => {
    let count = 0;

    // 1. Mark direct notifications
    const directNotifs = await ctx.db
      .query("user_notifications")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    for (const notif of directNotifs) {
      if (!notif.read) {
        await ctx.db.patch(notif._id, { read: true });
        count++;
      }
    }

    // 2. Mark broadcast notifications
    const broadcastNotifs = await ctx.db
      .query("user_notifications")
      .withIndex("by_target_type", (q) => q.eq("targetType", "all_users"))
      .take(50);

    for (const notif of broadcastNotifs) {
      const readList = notif.readByUsers ?? [];
      if (!readList.includes(args.userId)) {
        await ctx.db.patch(notif._id, {
          readByUsers: [...readList, args.userId],
        });
        count++;
      }
    }

    return count;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      ADMIN NOTIFICATION DISPATCH
// ═══════════════════════════════════════════════════════════════════════

/**
 * Inserts a sent notification record into the user_notifications table.
 */
export const createNotificationRecord = mutation({
  args: {
    targetType: v.union(v.literal("all_users"), v.literal("single_user")),
    userId: v.optional(v.string()),
    title: v.string(),
    body: v.string(),
    deepLinkScreen: v.optional(v.string()),
    deepLinkId: v.optional(v.string()),
    data: v.optional(v.string()),
  },
  returns: v.object({
    id: v.string(),
    createdAt: v.number(),
  }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const id = await ctx.db.insert("user_notifications", {
      targetType: args.targetType,
      userId: args.userId,
      title: args.title,
      body: args.body,
      deepLinkScreen: args.deepLinkScreen,
      deepLinkId: args.deepLinkId,
      data: args.data,
      read: false,
      readByUsers: [],
      createdAt: now,
    });

    return { id: id as string, createdAt: now };
  },
});

/**
 * Admin query to inspect all sent notifications and delivery logs.
 */
export const getAllNotificationsAdmin = query({
  args: {
    limit: v.optional(v.number()),
  },
  returns: v.array(
    v.object({
      id: v.string(),
      targetType: v.string(),
      userId: v.optional(v.string()),
      title: v.string(),
      body: v.string(),
      deepLinkScreen: v.optional(v.string()),
      deepLinkId: v.optional(v.string()),
      read: v.boolean(),
      readCount: v.number(),
      createdAt: v.number(),
    })
  ),
  handler: async (ctx, args) => {
    const takeCount = args.limit ?? 50;
    const notifs = await ctx.db
      .query("user_notifications")
      .order("desc")
      .take(takeCount);

    return notifs.map((n) => ({
      id: n._id as string,
      targetType: n.targetType,
      userId: n.userId,
      title: n.title,
      body: n.body,
      deepLinkScreen: n.deepLinkScreen,
      deepLinkId: n.deepLinkId,
      read: n.read,
      readCount: (n.readByUsers ?? []).length,
      createdAt: n.createdAt,
    }));
  },
});
