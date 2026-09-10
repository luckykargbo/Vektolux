// convex/emails.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Transactional Email & OTP Dispatch Service (Resend)
// ═══════════════════════════════════════════════════════════════════════

import { internalAction } from "./_generated/server";
import { v } from "convex/values";

export const sendOtpEmail = internalAction({
  args: {
    to: v.string(),
    otpCode: v.string(),
    recipientName: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) {
      console.warn("[Vektolux Mailer] RESEND_API_KEY is not configured. Email skipped.");
      return { success: false, error: "RESEND_API_KEY not configured" };
    }

    // Use custom from address or default to Resend verified testing address
    const fromAddress = process.env.RESEND_FROM_EMAIL || "Vektolux Security <onboarding@resend.dev>";

    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: fromAddress,
          to: [args.to],
          subject: `Your Vektolux Verification Code: ${args.otpCode}`,
          html: `
            <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 32px 24px; border: 1px solid #E2E8F0; border-radius: 16px; background-color: #ffffff;">
              <div style="text-align: center; margin-bottom: 28px;">
                <h1 style="color: #0F172A; margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;">VEKTOLUX</h1>
                <p style="color: #10B981; font-size: 11px; font-weight: 700; margin-top: 4px; text-transform: uppercase; letter-spacing: 1.5px;">Escrow & Mobility Security</p>
              </div>
              <p style="color: #334155; font-size: 15px; line-height: 1.6; margin-bottom: 12px;">
                Hello${args.recipientName ? ` <strong>${args.recipientName}</strong>` : ""},
              </p>
              <p style="color: #334155; font-size: 15px; line-height: 1.6; margin-bottom: 24px;">
                You requested a verification code to access your Vektolux account. Please enter the 6-digit code below:
              </p>
              <div style="background-color: #F8FAFC; border: 2px dashed #CBD5E1; border-radius: 12px; padding: 20px; text-align: center; margin: 28px 0;">
                <span style="font-size: 38px; font-weight: 800; color: #0F172A; letter-spacing: 10px; font-family: monospace;">${args.otpCode}</span>
              </div>
              <p style="color: #64748B; font-size: 13px; line-height: 1.5; margin-bottom: 24px;">
                This code is valid for <strong>10 minutes</strong>. If you did not request this code, please disregard this email. Your Vektolux account remains secure.
              </p>
              <hr style="border: none; border-top: 1px solid #E2E8F0; margin: 24px 0;" />
              <p style="color: #94A3B8; font-size: 11px; text-align: center; margin: 0; line-height: 1.4;">
                © 2026 Vektolux Technologies. Freetown, Sierra Leone.<br/>
                Protected by Vektolux Escrow Vault.
              </p>
            </div>
          `,
        }),
      });

      const data = await response.json();
      if (!response.ok) {
        console.error("[Vektolux Mailer] Resend API error:", data);
        return { success: false, error: data };
      }

      console.log(`[Vektolux Mailer] Dispatched OTP ${args.otpCode} to ${args.to} (ID: ${data.id})`);
      return { success: true, id: data.id };
    } catch (error) {
      console.error("[Vektolux Mailer] Network error sending email:", error);
      return { success: false, error: String(error) };
    }
  },
});
