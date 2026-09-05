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

enum IdDocumentType {
  nationalId,
  ecowasCard,
  passport,
}

extension IdDocumentTypeX on IdDocumentType {
  String get displayName => switch (this) {
        IdDocumentType.nationalId => 'Sierra Leone National ID (NIN)',
        IdDocumentType.ecowasCard => 'ECOWAS Biometric Card',
        IdDocumentType.passport => 'International Passport',
      };

  String get convexKey => switch (this) {
        IdDocumentType.nationalId => 'national_id',
        IdDocumentType.ecowasCard => 'ecowas_card',
        IdDocumentType.passport => 'passport',
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
