// lib/features/auth/domain/entities/user_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — User Domain Entity
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

/// User roles available in the Vektolux platform.
enum UserRole {
  client,     // Regular Client / Buyer
  agent,      // Real Estate Agent / Property Owner
  merchant,   // Vehicle Merchant / Auto Dealership
  driver,     // Commercial Fleet & Logistics Operator
  admin,      // Platform administrator
}

extension UserRoleX on UserRole {
  String get displayName => switch (this) {
    UserRole.client => 'Client / Buyer',
    UserRole.agent => 'Real Estate Agent',
    UserRole.merchant => 'Vehicle Merchant',
    UserRole.driver => 'Fleet & Logistics Operator',
    UserRole.admin => 'Administrator',
  };

  String get description => switch (this) {
    UserRole.client => 'Explore properties, buy vehicles & book logistics',
    UserRole.agent => 'List houses for sale, rent, or hourly guest houses',
    UserRole.merchant => 'List cars, vans & trucks for sale or rental',
    UserRole.driver => 'Manage commercial delivery vans & heavy trucks',
    UserRole.admin => 'Platform management',
  };

  String get iconName => switch (this) {
    UserRole.client => 'person',
    UserRole.agent => 'home_work',
    UserRole.merchant => 'directions_car',
    UserRole.driver => 'local_shipping',
    UserRole.admin => 'admin_panel_settings',
  };

  /// Whether this role requires business registration / TIN.
  bool get requiresBusinessInfo => this == UserRole.agent || this == UserRole.merchant;

  /// Convert to Convex string value.
  String get convexValue => name;

  /// Parse from Convex string value.
  static UserRole fromConvex(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.client,
    );
  }
}

/// Immutable user entity for the auth domain layer.
class UserEntity extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool isVerified;
  final String? avatarUrl;
  final String? walletAddress;
  final String? sessionToken;
  final String verificationStatus; // 'unverified', 'pending', 'verified', 'approved', 'rejected', 'suspended'
  final String verificationBadge;  // 'NONE', 'GREEN_TICK'
  final String activeMode;         // 'passenger' | 'driver'
  final bool isDriverVerified;
  final String driverStatus;       // 'offline' | 'online' | 'busy'
  final String? businessName;
  final String? tinNumber;
  final String? documentUrl;
  final String? rejectionReason;
  final int? verifiedAt;
  final String? bio;
  final String? kycStatus;

  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.isVerified = false,
    this.avatarUrl,
    this.walletAddress,
    this.sessionToken,
    this.verificationStatus = 'unverified',
    this.verificationBadge = 'NONE',
    this.activeMode = 'passenger',
    this.isDriverVerified = false,
    this.driverStatus = 'offline',
    this.businessName,
    this.tinNumber,
    this.documentUrl,
    this.rejectionReason,
    this.verifiedAt,
    this.bio,
    this.kycStatus,
  });

  bool get isDriverMode => activeMode == 'driver';
  bool get canSwitchToDriver => isDriverVerified || role == UserRole.driver;

  /// Verification status helpers
  bool get isPendingVerification => verificationStatus == 'pending';
  bool get isApprovedVerification => verificationStatus == 'approved' || verificationStatus == 'verified';
  bool get isRejectedVerification => verificationStatus == 'rejected';

  /// Role permission helpers for client isolation & sandbox enforcement
  bool get isNormalClient => role == UserRole.client;
  bool get canPostRealEstate => (role == UserRole.agent && isApprovedVerification) || role == UserRole.admin;
  bool get canPostVehicle => (role == UserRole.merchant && isApprovedVerification) || role == UserRole.admin;
  bool get canPostAnyListing => canPostRealEstate || canPostVehicle;

  UserEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    bool? isVerified,
    String? avatarUrl,
    String? walletAddress,
    String? sessionToken,
    String? verificationStatus,
    String? verificationBadge,
    String? activeMode,
    bool? isDriverVerified,
    String? driverStatus,
    String? businessName,
    String? tinNumber,
    String? documentUrl,
    String? rejectionReason,
    int? verifiedAt,
    String? bio,
    String? kycStatus,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      walletAddress: walletAddress ?? this.walletAddress,
      sessionToken: sessionToken ?? this.sessionToken,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationBadge: verificationBadge ?? this.verificationBadge,
      activeMode: activeMode ?? this.activeMode,
      isDriverVerified: isDriverVerified ?? this.isDriverVerified,
      driverStatus: driverStatus ?? this.driverStatus,
      businessName: businessName ?? this.businessName,
      tinNumber: tinNumber ?? this.tinNumber,
      documentUrl: documentUrl ?? this.documentUrl,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      bio: bio ?? this.bio,
      kycStatus: kycStatus ?? this.kycStatus,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        phone,
        role,
        isVerified,
        avatarUrl,
        walletAddress,
        sessionToken,
        verificationStatus,
        verificationBadge,
        activeMode,
        isDriverVerified,
        driverStatus,
        businessName,
        tinNumber,
        documentUrl,
        rejectionReason,
        verifiedAt,
        bio,
        kycStatus,
      ];
}
