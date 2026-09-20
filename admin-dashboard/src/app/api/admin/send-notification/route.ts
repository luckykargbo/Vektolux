// src/app/api/admin/send-notification/route.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Admin Notification Dispatch API
// Inserts into Convex database, triggers FCM push notification,
// and packages deep-link data for Android, iOS, & Web.
// ═══════════════════════════════════════════════════════════════════════

import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { sendPushNotification } from "@/lib/firebase-admin";

import { CONVEX_URL } from "@/lib/convex";

function getConvexClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const {
      targetType, // "all_users" | "single_user"
      userId,
      title,
      message,
      deepLinkScreen,
      deepLinkId,
    } = body;

    // Validation
    if (!title || !message) {
      return NextResponse.json(
        { success: false, error: "Title and message body are required." },
        { status: 400 }
      );
    }

    if (targetType === "single_user" && !userId) {
      return NextResponse.json(
        { success: false, error: "userId is required when target is single_user." },
        { status: 400 }
      );
    }

    const convex = getConvexClient();

    // 1. Insert notification record into Convex database table `user_notifications`
    const dbRecord: any = await convex.mutation("notifications:createNotificationRecord" as any, {
      targetType: targetType === "single_user" ? "single_user" : "all_users",
      userId: targetType === "single_user" ? userId : undefined,
      title: title.trim(),
      body: message.trim(),
      deepLinkScreen: deepLinkScreen || undefined,
      deepLinkId: deepLinkId || undefined,
      data: JSON.stringify({
        deepLinkScreen: deepLinkScreen || "notifications",
        deepLinkId: deepLinkId || "",
      }),
    });

    // 2. Fetch device tokens if targeting a specific user
    let recipientTokens: string[] = [];
    if (targetType === "single_user") {
      try {
        const tokens: any[] = await convex.query("notifications:getUserTokens" as any, {
          userId,
        });
        recipientTokens = (tokens || []).map((t) => t.fcmToken);
      } catch (err) {
        console.warn("[send-notification] Failed to query user tokens:", err);
      }
    }

    // 3. Dispatch Push via Firebase Admin SDK
    const pushResult = await sendPushNotification({
      target:
        targetType === "single_user"
          ? {
              type: "tokens",
              tokens: recipientTokens,
            }
          : {
              type: "topic",
              topic: "all_users",
            },
      title: title.trim(),
      body: message.trim(),
      deepLinkScreen: deepLinkScreen || "notifications",
      deepLinkId: deepLinkId || "",
      extraData: {
        notificationId: dbRecord?.id || "",
      },
    });

    return NextResponse.json({
      success: true,
      data: {
        notificationId: dbRecord?.id,
        createdAt: dbRecord?.createdAt,
        pushResult,
        tokensCount: recipientTokens.length,
      },
    });
  } catch (err: any) {
    console.error("[send-notification POST] Error:", err);
    return NextResponse.json(
      { success: false, error: err?.message || "Internal server error occurred." },
      { status: 500 }
    );
  }
}

export async function GET() {
  try {
    const convex = getConvexClient();
    const history = await convex.query("notifications:getAllNotificationsAdmin" as any, {
      limit: 50,
    });
    return NextResponse.json({ success: true, data: history });
  } catch (err: any) {
    console.error("[send-notification GET] Error:", err);
    return NextResponse.json(
      { success: false, error: err?.message || "Failed to fetch notification history." },
      { status: 500 }
    );
  }
}
