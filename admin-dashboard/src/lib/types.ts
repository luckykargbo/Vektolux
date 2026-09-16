// src/lib/types.ts
// Shared TypeScript types for Vektolux Admin Dashboard

export type VerificationStatus = "pending" | "approved" | "rejected" | "all";

export interface VerificationEntry {
  userId: string;
  name: string;
  email: string;
  phone: string;
  businessName: string;
  tinNumber: string;
  documentType?: string;
  documentUrl?: string;
  documentStorageId?: string;
  verificationStatus: string;
  rejectionReason?: string;
  verifiedAt?: number;
  createdAt: number;
  updatedAt?: number;
}

export interface AdminListing {
  id: string;
  type: "property" | "vehicle";
  title: string;
  price: number;
  city: string;
  isPublished: boolean;
  ownerId: string;
  ownerName?: string;
  imageUrls?: string[];
  createdAt: number;
}

export interface AdminUser {
  id: string;
  name: string;
  email: string;
  sessionToken: string;
}

export interface AdminSession {
  user: AdminUser;
  loggedInAt: number;
}

export interface UserRecord {
  id: string;
  name: string;
  email: string;
  phone: string;
  role: string;
  activeRole?: string;
  isVerified: boolean;
  verificationStatus: string;
  isActive: boolean;
  businessName?: string;
  tinNumber?: string;
  avatarUrl?: string;
  walletAddress?: string;
  createdAt: number;
  updatedAt?: number;
}

