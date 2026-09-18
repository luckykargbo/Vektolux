// lib/features/verification/domain/entities/verification_record.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Verification Domain Entities & States
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

enum VerificationStatus {
  unverified,
  pending,
  verified,
  rejected,
}

extension VerificationStatusX on VerificationStatus {
  String get displayName => switch (this) {
        VerificationStatus.unverified => 'Unverified',
        VerificationStatus.pending => 'Pending Review',
        VerificationStatus.verified => 'Verified Seller',
        VerificationStatus.rejected => 'Action Required',
      };

  bool get isVerified => this == VerificationStatus.verified;
  bool get isPending => this == VerificationStatus.pending;
  bool get canList => this == VerificationStatus.verified;

  static VerificationStatus fromString(String? value) {
    return switch (value?.toLowerCase()) {
      'verified' => VerificationStatus.verified,
      'pending' => VerificationStatus.pending,
      'rejected' => VerificationStatus.rejected,
      _ => VerificationStatus.unverified,
    };
  }
}

enum AccountType {
  individual,
  business,
}

extension AccountTypeX on AccountType {
  String get displayName => switch (this) {
        AccountType.individual => 'Individual Agent / Owner',
        AccountType.business => 'Registered Company / Agency',
      };

  String get convexKey => switch (this) {
        AccountType.individual => 'INDIVIDUAL',
        AccountType.business => 'BUSINESS',
      };

  static AccountType fromString(String? value) {
    return switch (value?.toUpperCase()) {
      'BUSINESS' => AccountType.business,
      _ => AccountType.individual,
    };
  }
}

enum IdDocumentType {
  nationalId,
  voterId,
  driverLicense,
  ecowasCard,
  passport,
}

extension IdDocumentTypeX on IdDocumentType {
  String get displayName => switch (this) {
        IdDocumentType.nationalId => 'Sierra Leone National ID (NIN)',
        IdDocumentType.voterId => 'Sierra Leone Voter ID Card',
        IdDocumentType.driverLicense => 'SLRSA Driver License',
        IdDocumentType.ecowasCard => 'ECOWAS Biometric Card',
        IdDocumentType.passport => 'International Passport',
      };

  String get convexKey => switch (this) {
        IdDocumentType.nationalId => 'NATIONAL_ID',
        IdDocumentType.voterId => 'VOTER_ID',
        IdDocumentType.driverLicense => 'DRIVER_LICENSE',
        IdDocumentType.ecowasCard => 'national_id',
        IdDocumentType.passport => 'national_id',
      };
}

class VerificationRecord extends Equatable {
  final String id;
  final String userId;
  final String referenceId;
  final IdDocumentType documentType;
  final VerificationStatus status;
  final double? livenessScore;
  final double? faceMatchScore;
  final bool? mrzValidated;
  final bool? tamperingPassed;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? completedAt;

  const VerificationRecord({
    required this.id,
    required this.userId,
    required this.referenceId,
    required this.documentType,
    required this.status,
    this.livenessScore,
    this.faceMatchScore,
    this.mrzValidated,
    this.tamperingPassed,
    this.rejectionReason,
    required this.createdAt,
    this.completedAt,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        referenceId,
        documentType,
        status,
        livenessScore,
        faceMatchScore,
        mrzValidated,
        tamperingPassed,
        rejectionReason,
        createdAt,
        completedAt,
      ];
}
