// lib/features/mobility/domain/entities/nearby_seller_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Verified Merchant & Seller Proximity Domain Entity
// Represents registered vendors/merchants across Sierra Leone provinces.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

class NearbySellerEntity extends Equatable {
  final String id;
  final String businessName;
  final String ownerName;
  final String category; // 'Auto Parts & Fleet', 'Electronics', 'Provisions', etc.
  final String phone;
  final String? avatarUrl;
  final double latitude;
  final double longitude;
  final String address;
  final double rating;
  final int totalSales;
  final bool isVerified;
  final double distanceKm;
  final int etaMinutes;

  const NearbySellerEntity({
    required this.id,
    required this.businessName,
    required this.ownerName,
    required this.category,
    required this.phone,
    this.avatarUrl,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.rating = 4.9,
    this.totalSales = 240,
    this.isVerified = true,
    this.distanceKm = 1.2,
    this.etaMinutes = 6,
  });

  @override
  List<Object?> get props => [
        id,
        businessName,
        ownerName,
        category,
        phone,
        avatarUrl,
        latitude,
        longitude,
        address,
        rating,
        totalSales,
        isVerified,
        distanceKm,
        etaMinutes,
      ];
}
