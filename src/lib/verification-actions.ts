"use server";

import { createClient } from "@supabase/supabase-js";

// Initialize Supabase admin client with service role key for protected server operations
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

// Client for regular operations and admin client for privileged verification actions
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

interface AuthUser {
  id: string;
  role?: string;
  email?: string;
}

/**
 * Helper to verify caller is an authenticated administrator
 */
async function verifyAdminCaller(accessToken: string): Promise<AuthUser> {
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    throw new Error("Authentication failed: User not logged in.");
  }

  // Check admin role from profile
  const { data: profile, error: profileError } = await supabaseAdmin
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profileError || profile?.role !== "admin") {
    throw new Error("Forbidden: Only platform administrators can perform this action.");
  }

  return user;
}

/**
 * Submit Agent Business Verification Details & Proof Document
 * Validates document type (PDF/JPEG/PNG) and size (<= 5MB)
 * Uploads to business-documents/{userId}/* and updates profile to 'pending'
 */
export async function submitAgentVerification(formData: FormData, accessToken: string) {
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return { success: false, error: "Unauthorized. Please log in first." };
  }

  const businessName = formData.get("businessName") as string;
  const tinNumber = formData.get("tinNumber") as string;
  const file = formData.get("document") as File | null;

  if (!businessName || !businessName.trim()) {
    return { success: false, error: "Business name is required." };
  }
  if (!tinNumber || !tinNumber.trim()) {
    return { success: false, error: "Tax Identification Number (TIN) is required." };
  }
  if (!file) {
    return { success: false, error: "Proof document is required." };
  }

  // 1. Validate File Size (<= 5MB)
  const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB in bytes
  if (file.size > MAX_FILE_SIZE) {
    return { success: false, error: "File exceeds maximum size limit of 5MB." };
  }

  // 2. Validate MIME Type
  const ALLOWED_TYPES = ["application/pdf", "image/jpeg", "image/png"];
  if (!ALLOWED_TYPES.includes(file.type)) {
    return { success: false, error: "Invalid file format. Only PDF, JPEG, and PNG files are accepted." };
  }

  try {
    // 3. Upload file to private storage bucket: business-documents/{userId}/
    const fileExt = file.name.split(".").pop();
    const fileName = `${user.id}/proof-${Date.now()}.${fileExt}`;
    const fileBuffer = Buffer.from(await file.arrayBuffer());

    const { data: uploadData, error: uploadError } = await supabase.storage
      .from("business-documents")
      .upload(fileName, fileBuffer, {
        contentType: file.type,
        upsert: true,
      });

    if (uploadError) {
      return { success: false, error: `Document upload failed: ${uploadError.message}` };
    }

    // 4. Update agent profile to 'pending' status and store document reference
    const { error: updateError } = await supabaseAdmin
      .from("profiles")
      .update({
        business_name: businessName.trim(),
        tin_number: tinNumber.trim(),
        document_url: uploadData.path,
        verification_status: "pending",
        rejection_reason: null, // clear any previous rejection
      })
      .eq("id", user.id);

    if (updateError) {
      return { success: false, error: `Profile update failed: ${updateError.message}` };
    }

    return {
      success: true,
      message: "Business verification submitted successfully. Under administrative review.",
      documentPath: uploadData.path,
    };
  } catch (err: any) {
    return { success: false, error: err.message || "An unexpected error occurred." };
  }
}

/**
 * Generate a short-lived Signed URL for proof documents
 * Restricted strictly to platform administrators
 * Expiry: 15 minutes (900 seconds)
 */
export async function getSignedDocumentUrl(filePath: string, accessToken: string) {
  try {
    // Verify caller is admin
    await verifyAdminCaller(accessToken);

    const EXPIRES_IN_SECONDS = 900; // 15 minutes
    const { data, error } = await supabaseAdmin.storage
      .from("business-documents")
      .createSignedUrl(filePath, EXPIRES_IN_SECONDS);

    if (error || !data?.signedUrl) {
      return { success: false, error: error?.message || "Failed to generate signed document URL." };
    }

    return {
      success: true,
      signedUrl: data.signedUrl,
      expiresIn: EXPIRES_IN_SECONDS,
    };
  } catch (err: any) {
    return { success: false, error: err.message || "Access denied." };
  }
}

/**
 * Approve Agent Verification
 * Admin-only: sets status to 'approved', logs verified_at timestamp and admin ID
 */
export async function approveAgent(agentId: string, accessToken: string) {
  try {
    const admin = await verifyAdminCaller(accessToken);

    const { error } = await supabaseAdmin
      .from("profiles")
      .update({
        verification_status: "approved",
        rejection_reason: null,
        verified_at: new Date().toISOString(),
        verified_by: admin.id,
      })
      .eq("id", agentId);

    if (error) {
      return { success: false, error: `Approval failed: ${error.message}` };
    }

    return {
      success: true,
      message: `Agent ${agentId} successfully approved.`,
    };
  } catch (err: any) {
    return { success: false, error: err.message || "Unauthorized operation." };
  }
}

/**
 * Reject Agent Verification
 * Admin-only: requires rejection reason, sets status to 'rejected'
 */
export async function rejectAgent(agentId: string, reason: string, accessToken: string) {
  if (!reason || !reason.trim()) {
    return { success: false, error: "A rejection reason must be provided." };
  }

  try {
    await verifyAdminCaller(accessToken);

    const { error } = await supabaseAdmin
      .from("profiles")
      .update({
        verification_status: "rejected",
        rejection_reason: reason.trim(),
        verified_at: null,
      })
      .eq("id", agentId);

    if (error) {
      return { success: false, error: `Rejection failed: ${error.message}` };
    }

    return {
      success: true,
      message: `Agent ${agentId} has been rejected with reason provided.`,
    };
  } catch (err: any) {
    return { success: false, error: err.message || "Unauthorized operation." };
  }
}

/**
 * Get Verification Queue for Admin Dashboard
 * Filterable by 'pending' | 'approved' | 'rejected' | 'all'
 */
export async function getVerificationQueue(
  statusFilter: "pending" | "approved" | "rejected" | "all" = "pending",
  accessToken: string
) {
  try {
    await verifyAdminCaller(accessToken);

    let query = supabaseAdmin
      .from("profiles")
      .select("id, name, email, phone, business_name, tin_number, document_url, verification_status, rejection_reason, verified_at, created_at")
      .eq("role", "agent");

    if (statusFilter !== "all") {
      query = query.eq("verification_status", statusFilter);
    }

    const { data, error } = await query.order("created_at", { ascending: false });

    if (error) {
      return { success: false, error: error.message };
    }

    return { success: true, queue: data };
  } catch (err: any) {
    return { success: false, error: err.message || "Unauthorized." };
  }
}
