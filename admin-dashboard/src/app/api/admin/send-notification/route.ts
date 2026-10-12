// src/app/api/admin/send-notification/route.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Admin Notification Dispatch API
// Inserts an in-app notification record into Convex (shown in the app's Notifications screen).
// There is NO device push: the app has no push provider, so none is claimed or simulated.
// ═══════════════════════════════════════════════════════════════════════

import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

function getConvexClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
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

    // The Convex backend only accepts this from an authenticated administrator session.
    const sessionToken = sessionFromRequest(request);
    if (!sessionToken) {
      return NextResponse.json({ success: false, error: "Administrator session required." }, { status: 401 });
    }
    const convex = getConvexClient();

    // 1. Insert notification record into Convex database table `user_notifications`
    const dbRecord: any = await convex.mutation("notifications:createNotificationRecord" as any, {
      sessionToken,
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

    return NextResponse.json({
      success: true,
      data: {
        notificationId: dbRecord?.id,
        createdAt: dbRecord?.createdAt,
        delivery: "in_app",
      },
    });
  } catch (err: any) {
    console.error("[send-notification POST] request failed");
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Internal server error occurred.") },
      { status: 500 }
    );
  }
}

export async function GET(request: Request) {
  try {
    const convex = getConvexClient();
    const history = await convex.query("notifications:getAllNotificationsAdmin" as any, {
      limit: 50,
      sessionToken: sessionFromRequest(request),
    });
    return NextResponse.json({ success: true, data: history });
  } catch (err: any) {
    console.error("[send-notification GET] request failed");
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Failed to fetch notification history.") },
      { status: 500 }
    );
  }
}
