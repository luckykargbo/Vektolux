// src/app/api/admin/api-health/route.ts
// Gateway health status and diagnostic ping endpoint
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

export const dynamic = "force-dynamic";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId") ?? undefined;
    const sessionToken = sessionFromRequest(request);

    const client = getClient();
    const result = await client.query(
      "adminPortal:getApiGatewayHealthPanel" as any,
      {
        adminId: adminId || undefined,
        sessionToken: sessionToken || undefined,
      }
    );

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[api-health GET] request failed");
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Failed to fetch gateway health.") },
      { status: 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      action?: "ping" | "update-mask";
      serviceId: string;
      keyName?: string;
      newMaskedValue?: string;
      healthStatus?: "operational" | "degraded" | "outage";
      adminId?: string;
    };

    if (!body.serviceId) {
      return NextResponse.json(
        { success: false, error: "serviceId is required." },
        { status: 400 }
      );
    }

    const client = getClient();
    if (body.action === "update-mask" && body.keyName && body.newMaskedValue) {
      const result = await client.mutation(
        "adminPortal:updateGatewayKeyMask" as any,
        {
          serviceId: body.serviceId,
          keyName: body.keyName,
          newMaskedValue: body.newMaskedValue,
          healthStatus: body.healthStatus || "operational",
          adminId: body.adminId || undefined,
          sessionToken: sessionFromRequest(request),
        }
      );
      return NextResponse.json({ success: true, data: result });
    }

    const result = await client.action(
      "adminPortal:testApiGatewayPing" as any,
      {
        serviceId: body.serviceId,
        adminId: body.adminId || undefined,
        sessionToken: sessionFromRequest(request),
      }
    );

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[api-health POST] request failed");
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Diagnostic ping failed.") },
      { status: 500 }
    );
  }
}
