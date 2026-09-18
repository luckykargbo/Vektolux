// src/lib/firebase-admin.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Firebase Admin SDK Integration (FCM Push Service)
// Handles server-side push notification delivery to Android, iOS, & Web.
// ═══════════════════════════════════════════════════════════════════════

import { getApps, initializeApp, cert } from "firebase-admin/app";
import { getMessaging, Message, MulticastMessage } from "firebase-admin/messaging";

interface PushPayload {
  target: {
    type: "topic" | "tokens";
    topic?: string;
    tokens?: string[];
  };
  title: string;
  body: string;
  deepLinkScreen?: string;
  deepLinkId?: string;
  extraData?: Record<string, string>;
}

interface PushResult {
  success: boolean;
  mode: "live_fcm" | "simulated_dev";
  messageId?: string;
  successCount?: number;
  failureCount?: number;
  error?: string;
}

let isInitialized = false;
let isSimulatedMode = false;

function initFirebaseAdmin(): boolean {
  if (isInitialized) return !isSimulatedMode;

  try {
    if (getApps().length > 0) {
      isInitialized = true;
      return true;
    }

    const projectId = process.env.FIREBASE_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const rawPrivateKey = process.env.FIREBASE_PRIVATE_KEY;

    if (projectId && clientEmail && rawPrivateKey) {
      const privateKey = rawPrivateKey.replace(/\\n/g, "\n");

      initializeApp({
        credential: cert({
          projectId,
          clientEmail,
          privateKey,
        }),
      });

      console.log("[FCM] Firebase Admin SDK initialized successfully.");
      isInitialized = true;
      isSimulatedMode = false;
      return true;
    } else {
      console.warn(
        "[FCM] Firebase credentials not configured in environment (FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY). Running in simulated development mode."
      );
      isInitialized = true;
      isSimulatedMode = true;
      return false;
    }
  } catch (err) {
    console.error("[FCM] Failed to initialize Firebase Admin SDK:", err);
    isInitialized = true;
    isSimulatedMode = true;
    return false;
  }
}

/**
 * Dispatches a push notification via FCM with high priority, sound, and deep-link payload.
 */
export async function sendPushNotification(payload: PushPayload): Promise<PushResult> {
  const isLive = initFirebaseAdmin();

  // Data payload for deep-linking (all values must be strings)
  const dataBlock: Record<string, string> = {
    title: payload.title,
    body: payload.body,
    click_action: "FLUTTER_NOTIFICATION_CLICK",
    deepLinkScreen: payload.deepLinkScreen || "notifications",
    deepLinkId: payload.deepLinkId || "",
    timestamp: Date.now().toString(),
    ...(payload.extraData || {}),
  };

  // If running in development simulation mode without credentials:
  if (!isLive || isSimulatedMode) {
    const mockId = `sim_msg_${Date.now()}_${Math.random().toString(36).substring(7)}`;
    console.log("[FCM Simulated] Notification dispatched:", {
      target: payload.target,
      title: payload.title,
      body: payload.body,
      data: dataBlock,
    });
    return {
      success: true,
      mode: "simulated_dev",
      messageId: mockId,
      successCount: payload.target.type === "topic" ? 1 : (payload.target.tokens?.length ?? 1),
      failureCount: 0,
    };
  }

  // Live FCM Dispatch via Firebase Admin SDK
  try {
    const messaging = getMessaging();

    if (payload.target.type === "topic") {
      const topicName = payload.target.topic || "all_users";

      const message: Message = {
        topic: topicName,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: dataBlock,
        android: {
          priority: "high",
          notification: {
            channelId: "vektolux_high_importance",
            priority: "high",
            sound: "default",
            defaultVibrateTimings: true,
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              alert: {
                title: payload.title,
                body: payload.body,
              },
              sound: "default",
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      };

      const response = await messaging.send(message);
      return {
        success: true,
        mode: "live_fcm",
        messageId: response,
        successCount: 1,
        failureCount: 0,
      };
    } else {
      // Multicast / direct device tokens
      const tokens = payload.target.tokens || [];
      if (tokens.length === 0) {
        return {
          success: false,
          mode: "live_fcm",
          error: "No device tokens found for target recipient.",
        };
      }

      const multicastMessage: MulticastMessage = {
        tokens,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: dataBlock,
        android: {
          priority: "high",
          notification: {
            channelId: "vektolux_high_importance",
            priority: "high",
            sound: "default",
            defaultVibrateTimings: true,
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              alert: {
                title: payload.title,
                body: payload.body,
              },
              sound: "default",
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      };

      const batchResponse = await messaging.sendEachForMulticast(multicastMessage);
      return {
        success: batchResponse.successCount > 0,
        mode: "live_fcm",
        successCount: batchResponse.successCount,
        failureCount: batchResponse.failureCount,
      };
    }
  } catch (err: any) {
    console.error("[FCM Live Error]:", err);
    return {
      success: false,
      mode: "live_fcm",
      error: err?.message || "Failed to dispatch message via FCM.",
    };
  }
}
