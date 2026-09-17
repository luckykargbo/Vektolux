// lib/features/mobility/domain/entities/escrow_order_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Escrow Order Domain Entity
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

enum EscrowOrderType {
  vehicleRental,
  vehiclePurchase,
}

enum EscrowOrderStatus {
  initiated,
  pendingPayment,
  heldInEscrow,
  partiallyReleased,
  postInspectionPending,
  settled,
  disputed,
  refunded,
  cancelled,
}

class EscrowOrderEntity extends Equatable {
  final String id;
  final String orderCode;
  final EscrowOrderType orderType;
  final String renterOrBuyerId;
  final String ownerOrSellerId;
  final String vehicleListingId;
  final String currency;

  final double baseRentalAmount;
  final double refundableDepositAmount;
  final double earnestFeeAmount;
  final double fullPurchaseAmount;

  final double grossEscrowAmount;
  final double platformFeeAmount;
  final double netMerchantExpected;

  final double split60ReleasedAmount;
  final double split40ReleasedAmount;
  final double depositRefundedAmount;
  final double depositDamageDeductedAmount;

  final EscrowOrderStatus status;
  final String? purchaseStage;

  final int? rentalStartDate;
  final int? rentalEndDate;
  final int? numberOfDays;

  final String? paymentProvider;
  final String? paymentPhone;

  final String? vehicleTitle;
  final String? vehicleCategory;
  final String? vehicleImage;
  final bool isOwner;

  final int createdAt;
  final int updatedAt;

  const EscrowOrderEntity({
    required this.id,
    required this.orderCode,
    required this.orderType,
    required this.renterOrBuyerId,
    required this.ownerOrSellerId,
    required this.vehicleListingId,
    required this.currency,
    required this.baseRentalAmount,
    required this.refundableDepositAmount,
    required this.earnestFeeAmount,
    required this.fullPurchaseAmount,
    required this.grossEscrowAmount,
    required this.platformFeeAmount,
    required this.netMerchantExpected,
    required this.split60ReleasedAmount,
    required this.split40ReleasedAmount,
    required this.depositRefundedAmount,
    required this.depositDamageDeductedAmount,
    required this.status,
    this.purchaseStage,
    this.rentalStartDate,
    this.rentalEndDate,
    this.numberOfDays,
    this.paymentProvider,
    this.paymentPhone,
    this.vehicleTitle,
    this.vehicleCategory,
    this.vehicleImage,
    this.isOwner = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EscrowOrderEntity.fromMap(Map<String, dynamic> map) {
    return EscrowOrderEntity(
      id: map['_id']?.toString() ?? '',
      orderCode: map['orderCode']?.toString() ?? '',
      orderType: map['orderType'] == 'VEHICLE_PURCHASE'
          ? EscrowOrderType.vehiclePurchase
          : EscrowOrderType.vehicleRental,
      renterOrBuyerId: map['renterOrBuyerId']?.toString() ?? '',
      ownerOrSellerId: map['ownerOrSellerId']?.toString() ?? '',
      vehicleListingId: map['vehicleListingId']?.toString() ?? '',
      currency: map['currency']?.toString() ?? 'SLE',
      baseRentalAmount: (map['baseRentalAmount'] as num?)?.toDouble() ?? 0.0,
      refundableDepositAmount: (map['refundableDepositAmount'] as num?)?.toDouble() ?? 0.0,
      earnestFeeAmount: (map['earnestFeeAmount'] as num?)?.toDouble() ?? 0.0,
      fullPurchaseAmount: (map['fullPurchaseAmount'] as num?)?.toDouble() ?? 0.0,
      grossEscrowAmount: (map['grossEscrowAmount'] as num?)?.toDouble() ?? 0.0,
      platformFeeAmount: (map['platformFeeAmount'] as num?)?.toDouble() ?? 0.0,
      netMerchantExpected: (map['netMerchantExpected'] as num?)?.toDouble() ?? 0.0,
      split60ReleasedAmount: (map['split60ReleasedAmount'] as num?)?.toDouble() ?? 0.0,
      split40ReleasedAmount: (map['split40ReleasedAmount'] as num?)?.toDouble() ?? 0.0,
      depositRefundedAmount: (map['depositRefundedAmount'] as num?)?.toDouble() ?? 0.0,
      depositDamageDeductedAmount: (map['depositDamageDeductedAmount'] as num?)?.toDouble() ?? 0.0,
      status: _parseStatus(map['status']?.toString()),
      purchaseStage: map['purchaseStage']?.toString(),
      rentalStartDate: (map['rentalStartDate'] as num?)?.toInt(),
      rentalEndDate: (map['rentalEndDate'] as num?)?.toInt(),
      numberOfDays: (map['numberOfDays'] as num?)?.toInt(),
      paymentProvider: map['paymentProvider']?.toString(),
      paymentPhone: map['paymentPhone']?.toString(),
      vehicleTitle: map['vehicleTitle']?.toString(),
      vehicleCategory: map['vehicleCategory']?.toString(),
      vehicleImage: map['vehicleImage']?.toString(),
      isOwner: map['isOwner'] == true,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  static EscrowOrderStatus _parseStatus(String? status) {
    switch (status) {
      case 'INITIATED':
        return EscrowOrderStatus.initiated;
      case 'PENDING_PAYMENT':
        return EscrowOrderStatus.pendingPayment;
      case 'HELD_IN_ESCROW':
        return EscrowOrderStatus.heldInEscrow;
      case 'PARTIALLY_RELEASED':
        return EscrowOrderStatus.partiallyReleased;
      case 'POST_INSPECTION_PENDING':
        return EscrowOrderStatus.postInspectionPending;
      case 'SETTLED':
        return EscrowOrderStatus.settled;
      case 'DISPUTED':
        return EscrowOrderStatus.disputed;
      case 'REFUNDED':
        return EscrowOrderStatus.refunded;
      default:
        return EscrowOrderStatus.cancelled;
    }
  }

  @override
  List<Object?> get props => [
        id,
        orderCode,
        orderType,
        renterOrBuyerId,
        ownerOrSellerId,
        vehicleListingId,
        grossEscrowAmount,
        status,
        updatedAt,
      ];
}
