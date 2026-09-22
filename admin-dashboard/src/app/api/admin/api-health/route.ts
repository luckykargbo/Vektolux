// src/app/api/admin/api-health/route.ts
// Gateway health status and diagnostic ping endpoint
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";

export const dynamic = "force-dynamic";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId") ?? undefined;
    const sessionToken = searchParams.get("sessionToken") ?? undefined;

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
    console.error("[api-health GET] error:", err);
    return NextResponse.json(
      { success: false, error: err?.message ?? "Failed to fetch gateway health." },
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
      sessionToken?: string;
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
          sessionToken: body.sessionToken || undefined,
        }
      );
      return NextResponse.json({ success: true, data: result });
    }

    const result = await client.mutation(
      "adminPortal:testApiGatewayPing" as any,
      {
        serviceId: body.serviceId,
        adminId: body.adminId || undefined,
        sessionToken: body.sessionToken || undefined,
      }
    );

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[api-health POST] error:", err);
    return NextResponse.json(
      { success: false, error: err?.message ?? "Diagnostic ping failed." },
      { status: 500 }
    );
  }
}
