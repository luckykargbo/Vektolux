// lib/features/mobility/domain/entities/driver_vehicle_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Vehicle Registration & Verification Entity
// Represents registered vehicle metadata, private KYC verification docs,
// and formatted customer-facing vehicle badges.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'nearby_driver_entity.dart';
import 'vehicle_tier_catalog.dart';

/// Driver vehicle verification state
enum DriverVehicleVerificationStatus {
  pending,
  approved,
  rejected;

  static DriverVehicleVerificationStatus fromString(String? val) {
    return switch (val?.toLowerCase().trim()) {
      'approved' => DriverVehicleVerificationStatus.approved,
      'rejected' => DriverVehicleVerificationStatus.rejected,
      _ => DriverVehicleVerificationStatus.pending,
    };
  }

  String get displayName => switch (this) {
        DriverVehicleVerificationStatus.pending => 'Under Review',
        DriverVehicleVerificationStatus.approved => 'Verified & Approved',
        DriverVehicleVerificationStatus.rejected => 'Action Required',
      };
}

/// Immutable domain entity representing a driver's registered vehicle.
class DriverVehicleEntity extends Equatable {
  final String id;
  final String driverId;
  final String vehicleType; // "keke" | "okada" | "car" | "van"
  final DriverVehicleCategory category;
  final String make;
  final String model;
  final int year;
  final String color;
  final String licensePlate;
  final DriverVehicleVerificationStatus verificationStatus;
  final bool isVerified;
  final String? licenseFrontUrl;
  final String? licenseBackUrl;
  final String? registrationDocUrl;
  final String? insuranceDocUrl;
  final String? inspectionPhotoUrl;
  final String? rejectionReason;
  final int? approvedAt;
  final int updatedAt;

  const DriverVehicleEntity({
    required this.id,
    required this.driverId,
    required this.vehicleType,
    required this.category,
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.licensePlate,
    this.verificationStatus = DriverVehicleVerificationStatus.pending,
    this.isVerified = false,
    this.licenseFrontUrl,
    this.licenseBackUrl,
    this.registrationDocUrl,
    this.insuranceDocUrl,
    this.inspectionPhotoUrl,
    this.rejectionReason,
    this.approvedAt,
    required this.updatedAt,
  });

  bool get isApproved => verificationStatus == DriverVehicleVerificationStatus.approved;
  bool get isPending => verificationStatus == DriverVehicleVerificationStatus.pending;
  bool get isRejected => verificationStatus == DriverVehicleVerificationStatus.rejected;

  /// Clean formatted text badge: `{Color} {Make} {Model} • {Plate Number}`
  /// Example: "Silver Toyota Corolla • SL-940-BA" or "Yellow Bajaj RE • SL-402-KE"
  String get formattedBadge {
    final parts = <String>[];
    if (color.trim().isNotEmpty) parts.add(color.trim());
    if (make.trim().isNotEmpty) parts.add(make.trim());
    if (model.trim().isNotEmpty) parts.add(model.trim());
    final vehicleDesc = parts.isNotEmpty ? parts.join(' ') : 'Commercial Vehicle';
    final plate = licensePlate.trim().isNotEmpty ? licensePlate.trim() : 'SL-PENDING';
    return '$vehicleDesc • $plate';
  }

  /// Map to corresponding 3D Isometric Vehicle Tier
  VehicleTierId get tierId {
    return switch (vehicleType.toLowerCase()) {
      'keke' => VehicleTierId.kekeBajaj,
      'okada' || 'bike' => VehicleTierId.okadaBike,
      'van' || 'cargo' => VehicleTierId.deliveryVan,
      _ => VehicleTierId.carStandard,
    };
  }

  factory DriverVehicleEntity.fromJson(Map<String, dynamic> json) {
    final catStr = json['category'] as String? ?? 'standard';
    return DriverVehicleEntity(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      driverId: json['driverId'] as String? ?? '',
      vehicleType: json['vehicleType'] as String? ?? 'car',
      category: DriverVehicleCategory.fromString(catStr),
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 2020,
      color: json['color'] as String? ?? '',
      licensePlate: (json['licensePlate'] as String? ?? '').toUpperCase(),
      verificationStatus: DriverVehicleVerificationStatus.fromString(
        json['verificationStatus'] as String?,
      ),
      isVerified: json['isVerified'] as bool? ?? false,
      licenseFrontUrl: json['licenseFrontUrl'] as String?,
      licenseBackUrl: json['licenseBackUrl'] as String?,
      registrationDocUrl: json['registrationDocUrl'] as String?,
      insuranceDocUrl: json['insuranceDocUrl'] as String?,
      inspectionPhotoUrl: json['inspectionPhotoUrl'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      approvedAt: (json['approvedAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  List<Object?> get props => [
        id,
        driverId,
        vehicleType,
        category,
        make,
        model,
        year,
        color,
        licensePlate,
        verificationStatus,
        isVerified,
        licenseFrontUrl,
        licenseBackUrl,
        registrationDocUrl,
        insuranceDocUrl,
        inspectionPhotoUrl,
        rejectionReason,
        approvedAt,
        updatedAt,
      ];
}
