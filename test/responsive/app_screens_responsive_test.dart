// Every user-facing screen rendered at real phone sizes — small Android (320/360pt), iPhone SE
// (375pt), iPhone 15 (393pt), Pixel (412pt), Pro Max (430pt) — with normal and large system text,
// against a fake backend that returns realistic, LONG data (long names and titles, prices in the
// hundreds of millions). Each screen is scrolled to the end so lazily built rows are laid out too.
// Any overflow or other framework error fails the test with the full diagnostic.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/core/widgets/app_text_scale.dart';
import 'package:vektolux/features/agent/data/agent_api.dart';
import 'package:vektolux/features/agent/domain/agent_models.dart';
import 'package:vektolux/features/agent/presentation/bloc/agent_workspace_cubit.dart';
import 'package:vektolux/features/agent/presentation/views/agent_add_listing_screen.dart';
import 'package:vektolux/features/agent/presentation/views/agent_listings_screen.dart';
import 'package:vektolux/features/agent/presentation/views/agent_messages_screen.dart';
import 'package:vektolux/features/agent/presentation/views/agent_notifications_screen.dart';
import 'package:vektolux/features/agent/presentation/views/agent_profile_screen.dart';
import 'package:vektolux/features/agent/presentation/views/agent_shell.dart';
import 'package:vektolux/features/agent/presentation/views/agent_viewings_screen.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/auth/presentation/views/complete_profile_phone_screen.dart';
import 'package:vektolux/features/auth/presentation/views/forgot_password_screen.dart';
import 'package:vektolux/features/auth/presentation/views/login_screen.dart';
import 'package:vektolux/features/auth/presentation/views/pending_verification_screen.dart';
import 'package:vektolux/features/auth/presentation/views/register_screen.dart';
import 'package:vektolux/features/bookings/presentation/views/checkout_screen.dart';
import 'package:vektolux/features/bookings/presentation/views/my_bookings_screen.dart';
import 'package:vektolux/features/discovery/presentation/views/discovery_feed_screen.dart';
import 'package:vektolux/features/explore/presentation/views/explore_screen.dart';
import 'package:vektolux/features/home/presentation/views/client_home_screen.dart';
import 'package:vektolux/features/listings/presentation/views/create_listing_screen.dart';
import 'package:vektolux/features/listings/presentation/views/my_listings_screen.dart';
import 'package:vektolux/features/listings/presentation/views/property_detail_screen.dart';
import 'package:vektolux/features/listings/presentation/views/vehicle_detail_screen.dart';
import 'package:vektolux/features/messaging/data/messaging_api.dart';
import 'package:vektolux/features/messaging/presentation/buyer_messaging.dart';
import 'package:vektolux/features/messaging/presentation/conversation_screen.dart';
import 'package:vektolux/features/mobility/presentation/views/auto_marketplace_screen.dart';
import 'package:vektolux/features/mobility/presentation/views/delivery_van_booking_screen.dart';
import 'package:vektolux/features/mobility/presentation/views/escrow_checkout_screen.dart';
import 'package:vektolux/features/mobility/presentation/views/my_escrow_orders_screen.dart';
import 'package:vektolux/features/navigation/presentation/views/main_navigation_shell.dart';
import 'package:vektolux/features/notifications/presentation/views/notifications_screen.dart';
import 'package:vektolux/features/operator/presentation/views/operator_dashboard_screen.dart';
import 'package:vektolux/features/profile/presentation/views/profile_screen.dart';
import 'package:vektolux/features/real_estate/domain/entities/property_listing_entity.dart';
import 'package:vektolux/features/real_estate/presentation/views/inspection_pass_verification_screen.dart';
import 'package:vektolux/features/real_estate/presentation/views/my_real_estate_escrows_screen.dart';
import 'package:vektolux/features/real_estate/presentation/views/real_estate_escrow_checkout_screen.dart';
import 'package:vektolux/features/real_estate/presentation/views/real_estate_marketplace_screen.dart';
import 'package:vektolux/features/social/presentation/views/public_profile_screen.dart';
import 'package:vektolux/features/social/presentation/views/social_feed_screen.dart';
import 'package:vektolux/features/subscriptions/presentation/views/professional_subscription_screen.dart';
import 'package:vektolux/features/verification/presentation/views/agent_verification_screen.dart';
import 'package:vektolux/features/verification/presentation/views/identity_verification_screen.dart';
import 'package:vektolux/features/wallet_payments/presentation/bloc/wallet_cubit.dart';
import 'package:vektolux/features/wallet_payments/presentation/views/transaction_history_screen.dart';
import 'package:vektolux/features/wallet_payments/presentation/views/transaction_receipt_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

// ─── Phones ──────────────────────────────────────────────────────────────

class _Device {
  final String name;
  final double width;
  final double height;
  final double textScale;
  const _Device(this.name, this.width, this.height, this.textScale);
}

// "large text" = the phone's font size set to 150%; the app caps it at kMaxAppTextScale, exactly
// as on a device (the same AppTextScale wrapper as main.dart is applied below).
const _devices = <_Device>[
  _Device('320pt small phone, large text', 320, 568, 1.5),
  _Device('360pt Android', 360, 640, 1.0),
  _Device('360pt Android, large text', 360, 640, 1.5),
  _Device('375pt iPhone SE', 375, 667, 1.0),
  _Device('393pt iPhone 15', 393, 852, 1.0),
  _Device('412pt Pixel, large text', 412, 915, 1.5),
  _Device('430pt Pro Max', 430, 932, 1.0),
];

// ─── Realistic, long fixture data ────────────────────────────────────────

final int _now = DateTime.now().millisecondsSinceEpoch;
const _day = 86400000;
const _longName = 'Mohamed Abdulai Bangura-Kamara';
const _longTitle = 'Luxurious Five Bedroom Family Villa With Ocean View And Large Garden';

const _buyer = UserEntity(
  id: 'user_1',
  name: 'Aminata Fatmata Kamara-Conteh',
  email: 'aminata.fatmata.kamara.conteh@example.com',
  phone: '+23276123456',
  role: UserRole.client,
  isVerified: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_user_1_0123456789abcdef',
  bio: 'Looking for a family home close to good schools in the Western Area.',
  region: 'Western Area Urban',
);

const _seller = UserEntity(
  id: 'owner_1',
  name: _longName,
  email: 'mohamed.bangura.kamara@example.com',
  phone: '+23277987654',
  role: UserRole.agent,
  isVerified: true,
  isVerifiedSeller: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_owner_1_0123456789abcdef',
  businessName: 'Bangura-Kamara Premium Properties & Estates Ltd',
  tinNumber: 'TIN-SL-0049781234',
);

const _pendingBusiness = UserEntity(
  id: 'owner_2',
  name: _longName,
  email: 'pending.business@example.com',
  phone: '+23277000111',
  role: UserRole.agent,
  verificationStatus: 'pending',
  sessionToken: 'sess_owner_2_0123456789abcdef',
  businessName: 'Bangura-Kamara Premium Properties & Estates Ltd',
  tinNumber: 'TIN-SL-0049781234',
);

Map<String, dynamic> _property(int i, {String category = 'sale'}) => {
      '_id': 'prop_$i',
      'id': 'prop_$i',
      '_creationTime': _now - i * 60000,
      'ownerId': 'owner_1',
      'title': '$_longTitle #$i',
      'description':
          'Spacious villa with a large garden, boys quarters, 24/7 water supply, solar backup power and secure parking for four cars.',
      'category': category,
      'price': 1250000000,
      if (category == 'hourly_guesthouse') 'hourlyRate': 15000,
      'currency': 'SLE',
      'address': 'Inside Hill Station, Sierra Leone',
      'publicLocation': 'Inside Hill Station, Sierra Leone',
      'city': 'Hill Station',
      'district': 'Western Area Urban',
      'country': 'Sierra Leone',
      'bedrooms': 5,
      'bathrooms': 4,
      'areaSqM': 1250,
      'amenities': ['Parking', 'Generator / backup power', '24/7 Security', 'Water supply'],
      'imageUrls': <String>[],
      'availabilityStatus': 'available',
      'isFeatured': i == 0,
      'isPublished': true,
      'viewCount': 0,
      'updatedAt': _now,
      'ownerName': _longName,
      'isVerified': true,
      'type': 'property',
    };

Map<String, dynamic> _vehicle(int i, {String category = 'car_sale', String pricingType = 'total_sale'}) => {
      '_id': 'veh_$i',
      'id': 'veh_$i',
      'ownerId': 'owner_1',
      'title': '2023 Toyota Land Cruiser Prado VX Limited Edition #$i',
      'category': category,
      'price': pricingType == 'total_sale' ? 985000000 : 25000,
      'pricingType': pricingType,
      'capacity': '7 seats / 3.5 tonnes',
      'location': 'Inside Freetown, Sierra Leone',
      'publicLocation': 'Inside Freetown, Sierra Leone',
      'images': <String>[],
      'imageUrls': <String>[],
      'status': 'AVAILABLE',
      'make': 'Toyota',
      'model': 'Land Cruiser Prado VX Limited',
      'year': 2023,
      'mileage': 125000,
      'transmission': 'Automatic',
      'fuelType': 'Diesel',
      'serviceArea': 'Western Area Urban and Rural',
      'description': 'One owner, full service history, new tyres and a recent inspection report.',
      'currency': 'SLE',
      if (pricingType == 'per_day') 'pricePerDay': 25000,
      if (pricingType == 'total_sale') 'salePrice': 985000000,
      'availabilityStatus': 'available',
      'createdAt': _now - i * 60000,
      'listingIntent': pricingType == 'total_sale' ? 'sale' : 'rental',
      'vehicleType': category,
      'type': 'vehicle',
      'isPublished': true,
      'ownerName': _longName,
    };

Map<String, dynamic> _booking(int i, String status, String settlement) => {
      '_id': 'book_$i',
      'listingId': 'prop_$i',
      'listingType': 'property',
      'listingTitle': '$_longTitle #$i',
      'buyerId': 'user_1',
      'buyerName': _buyer.name,
      'vendorId': 'owner_1',
      'bookingType': 'instant_stay',
      'status': status,
      'startTime': _now + (i - 1) * _day,
      'endTime': _now + (i + 1) * _day,
      'hours': 48,
      'days': 2,
      'subtotal': 1500000,
      'serviceFee': 75000,
      'totalAmount': 1575000,
      'currency': 'SLE',
      'paymentStatus': status == 'pending' ? 'unpaid' : 'paid',
      'paymentMethod': 'wallet',
      'settlementStatus': settlement,
      'releaseEligibleAt': _now + (i + 2) * _day,
      'updatedAt': _now,
    };

final Map<String, Object? Function(Map<String, dynamic>)> _routes = {
  'realEstate:listProperties': (_) =>
      [_property(0), _property(1, category: 'long_term_rent'), _property(2, category: 'hourly_guesthouse')],
  'mobility:listVehicles': (_) => [
        _vehicle(0),
        _vehicle(1, category: 'car_rental', pricingType: 'per_day'),
        _vehicle(2, category: 'delivery_van', pricingType: 'per_trip'),
      ],
  'realEstate:getMyPropertyListings': (_) => [_property(0), _property(1, category: 'long_term_rent')],
  'mobility:getMyVehicleListings': (_) => [_vehicle(0)],
  'users:getWalletProfile': (_) => {
        'userId': 'user_1',
        'fullName': _buyer.name,
        'phone': _buyer.phone,
        'email': _buyer.email,
        'role': 'client',
        'avatarUrl': null,
        'address': 'Inside Hill Station, Sierra Leone',
        'region': 'Western Area Urban',
        'verificationStatus': 'VERIFIED',
        'verificationBadge': 'VERIFIED CITIZEN ID • ESCROW ENABLED',
        'isVerifiedSeller': false,
        'canPublishListings': false,
        'walletBalance': 125000750.55,
        'lockedEscrowBalance': 35000000.25,
        'currency': 'SLE',
        'activeEscrowDeals': 3,
        'qrPayload': 'vektolux://pay?userId=user_1',
      },
  'payments:getWalletBalance': (_) =>
      {'availableBalance': 125000750.55, 'pendingBalance': 2500000.0, 'escrowBalance': 35000000.25, 'currency': 'SLE'},
  'wallet:getUserBalance': (_) =>
      {'availableBalance': 125000750.55, 'pendingBalance': 2500000.0, 'escrowBalance': 35000000.25, 'currency': 'SLE'},
  'payments:getUserPaymentAccounts': (_) => [
        {
          '_id': 'pa1', 'userId': 'user_1', 'providerCode': 'orange', 'providerName': 'Orange Money Sierra Leone',
          'accountNumber': '+23276123456', 'maskedNumber': '****3456', 'isDefault': true, 'createdAt': _now,
        },
        {
          '_id': 'pa2', 'userId': 'user_1', 'providerCode': 'afrimoney', 'providerName': 'Africell Afrimoney',
          'accountNumber': '+23277123456', 'maskedNumber': '****3456', 'isDefault': false, 'createdAt': _now,
        },
      ],
  'escrow:getMyEscrowOrders': (_) => [
        {
          '_id': 'eo1', 'orderCode': 'VX-ESC-2026-000123', 'orderType': 'rental', 'renterOrBuyerId': 'user_1',
          'ownerOrSellerId': 'owner_1', 'vehicleListingId': 'veh_1', 'currency': 'SLE', 'baseRentalAmount': 750000,
          'refundableDepositAmount': 250000, 'grossEscrowAmount': 1000000, 'platformFeeAmount': 50000,
          'netMerchantExpected': 950000, 'status': 'HELD_IN_ESCROW', 'numberOfDays': 30,
          'rentalStartDate': _now, 'rentalEndDate': _now + 30 * _day, 'createdAt': _now, 'updatedAt': _now,
          'vehicleTitle': '2023 Toyota Land Cruiser Prado VX Limited Edition', 'vehicleCategory': 'car_rental',
          'vehicleImage': '', 'isOwner': false,
        },
        {
          '_id': 'eo2', 'orderCode': 'VX-ESC-2026-000124', 'orderType': 'purchase', 'renterOrBuyerId': 'user_1',
          'ownerOrSellerId': 'owner_1', 'vehicleListingId': 'veh_0', 'currency': 'SLE', 'fullPurchaseAmount': 985000000,
          'earnestFeeAmount': 9850000, 'grossEscrowAmount': 985000000, 'platformFeeAmount': 29550000,
          'netMerchantExpected': 955450000, 'status': 'POST_INSPECTION_PENDING', 'purchaseStage': 'INSPECTION',
          'createdAt': _now - _day, 'updatedAt': _now, 'vehicleTitle': '2023 Toyota Land Cruiser Prado VX Limited Edition',
          'vehicleCategory': 'car_sale', 'vehicleImage': '', 'isOwner': true,
        },
      ],
  'realEstateEscrow:getMyRealEstateEscrows': (_) => {
        'contracts': [
          {
            '_id': 'c1', 'contractCode': 'VX-RE-2026-000777', 'contractType': 'LONG_TERM_LEASE', 'propertyListingId': 'prop_1',
            'clientId': 'user_1', 'beneficiaryId': 'owner_1', 'grossAmount': 36000000, 'cautionDepositAmount': 3000000,
            'platformFeeAmount': 1080000, 'agentCommissionAmount': 0, 'netBeneficiaryExpected': 34920000,
            'releasedBeneficiaryAmount': 0, 'refundedClientAmount': 0, 'paymentRail': 'wallet', 'currentState': 'FUNDS_LOCKED',
            'leaseDurationMonths': 12, 'escrowHeldRemaining': 36000000, 'createdAt': _now, 'updatedAt': _now,
            'propertyTitle': '$_longTitle #1', 'propertyCategory': 'long_term_rent',
            'propertyCity': 'Inside Hill Station, Sierra Leone', 'propertyImage': '', 'isOwner': false,
          },
        ],
        'inspectionPasses': [
          {
            '_id': 'pass1', 'propertyListingId': 'prop_0', 'clientId': 'user_1', 'agentId': 'owner_1', 'tourFee': 150000,
            'platformFee': 15000, 'agentNetFee': 135000, 'status': 'FUNDS_LOCKED', 'scheduledAt': _now + _day,
            'isAddressUnmasked': false, 'createdAt': _now, 'otpCode': '482913', 'qrHash': 'abc123',
            'propertyTitle': '$_longTitle #0', 'propertyImage': '', 'isAgent': false,
          },
        ],
      },
  'bookings:getUserBookings': (_) =>
      [_booking(0, 'confirmed', 'held'), _booking(1, 'pending', 'held'), _booking(2, 'disputed', 'disputed'), _booking(3, 'completed', 'released')],
  'notifications:getUserNotifications': (_) => [
        {
          'id': 'n1', 'targetType': 'single_user', 'title': 'Booking payment released to your wallet successfully',
          'body': 'The payment for "$_longTitle" has been released to your wallet after the 24 hour protection window.',
          'read': false, 'createdAt': _now - 60000, 'deepLinkScreen': 'real_estate',
        },
        {
          'id': 'n2', 'targetType': 'all_users', 'title': 'Planned maintenance this weekend',
          'body': 'Vektolux will be unavailable on Saturday night between 1 AM and 3 AM for scheduled upgrades.',
          'read': true, 'createdAt': _now - 3 * _day,
        },
      ],
  'notifications:getUnreadNotificationCount': (_) => 12,
  'social:getSocialFeed': (_) => [_property(0), _vehicle(1, category: 'car_rental', pricingType: 'per_day')],
  'users:getUserProfile': (_) => {
        '_id': 'owner_1', 'name': _longName,
        'bio': 'Award-winning real estate professional helping families and investors across Freetown, Bo and Kenema for over twelve years.',
        'role': 'agent', 'verificationBadge': 'VERIFIED CITIZEN ID • ESCROW ENABLED', 'followersCount': 12500,
        'followingCount': 340, 'isVerified': true, 'isVerifiedSeller': true, 'canPublishListings': true,
      },
  'users:getUserPosts': (_) => [_property(0), _property(1, category: 'long_term_rent'), _vehicle(0)],
  'social:getFollowStatus': (_) => {'isFollowing': false},
  'subscriptions:getPlans': (_) => [
        {
          'id': 'plan1', 'name': 'Real Estate Agent Professional Annual', 'tierCode': 'agent_pro_annual', 'roleTarget': 'agent',
          'basePrice': 5000000, 'effectivePrice': 4250000, 'currency': 'SLE', 'billingInterval': 'annual', 'intervalDays': 365,
          'discountPercent': 15, 'isPromoActive': true, 'promoEnd': _now + 10 * _day,
          'features': ['Unlimited property listings', 'Verified agent badge on every listing', 'Priority placement in search results'],
        },
        {
          'id': 'plan2', 'name': 'Hotel & Guest House Monthly', 'tierCode': 'hotel_monthly', 'roleTarget': 'hotel_operator',
          'basePrice': 750000, 'effectivePrice': 750000, 'currency': 'SLE', 'billingInterval': 'monthly', 'intervalDays': 30,
          'discountPercent': 0, 'isPromoActive': false, 'features': ['Manage rooms and bookings', 'Verified hotel badge'],
        },
      ],
  'subscriptions:getMyProfessionalStatus': (a) => {
        'role': a['sessionToken'] == _seller.sessionToken ? 'real_estate_agent' : 'client',
        'roleApproved': a['sessionToken'] == _seller.sessionToken, 'verifiedAgent': false, 'verifiedHotel': false,
        'agentExpiresAt': null, 'hotelExpiresAt': null, 'hasActiveSubscription': false, 'isInGracePeriod': false,
        'gracePeriodEndsAt': null, 'legacyGraceEndedAt': null, 'subscriptionPolicyConfigured': false,
        'canPostProperty': false, 'canPostVehicle': false, 'canManageHotel': false, 'applications': [],
      },
  'walletCore:getUserTransactions': (_) => {
        'success': true,
        'transactions': [
          {
            'id': 't1', 'transactionId': 'VX-TXN-0000001234567', 'type': 'escrow_release', 'amount': 1250000.5, 'currency': 'SLE',
            'status': 'completed', 'description': 'Escrow release for "$_longTitle"', 'counterpartyName': _longName,
            'counterpartyPhone': '+23276999888', 'feeAmount': 12500, 'netAmount': 1237500.5, 'createdAt': _now,
          },
          {
            'id': 't2', 'transactionId': 'VX-TXN-0000001234568', 'type': 'deposit', 'amount': 125000000, 'currency': 'SLE',
            'status': 'completed', 'description': 'Orange Money deposit', 'gatewayProvider': 'monime', 'createdAt': _now - _day,
          },
          {
            'id': 't3', 'transactionId': 'VX-TXN-0000001234569', 'type': 'payout', 'amount': 2500000, 'currency': 'SLE',
            'status': 'failed', 'description': 'Withdrawal to Africell Afrimoney ****3456', 'failureReason': 'Provider timeout',
            'createdAt': _now - 2 * _day,
          },
        ],
      },
  'walletCore:getEarningsSummary': (_) => {'totalEarned': 98765432.1, 'currency': 'SLE', 'count': 128, 'truncated': false},
  'verification:getVerificationStatus': (_) => {'isVerified': true, 'status': 'verified'},
  'businessVerification:getMyVerificationStatus': (_) => {
        'verificationStatus': 'approved', 'businessName': 'Bangura-Kamara Premium Properties & Estates Ltd',
        'tinNumber': 'TIN-SL-0049781234',
      },
  'explore:getExploreFeed': (_) => {
        'recommended': [_property(0), _vehicle(0)],
        'propertiesNearYou': [_property(0), _property(1, category: 'long_term_rent'), _property(2, category: 'hourly_guesthouse')],
        'vehiclesForSaleAndHire': [
          _vehicle(0),
          _vehicle(1, category: 'car_rental', pricingType: 'per_day'),
          _vehicle(2, category: 'delivery_van', pricingType: 'per_trip'),
        ],
        'topAgentsAndDealers': [
          {'id': 'owner_1', 'name': _longName, 'role': 'Real Estate Agent', 'isVerified': true, 'listingsCount': 1580},
          {'id': 'owner_3', 'name': 'Freetown Premium Auto Dealers & Fleet Rentals', 'role': 'Auto Dealer', 'isVerified': false, 'listingsCount': 12},
        ],
      },
  'locations:getSierraLeoneLocations': (_) => [
        {'region': 'Western Area', 'district': 'Western Area Urban', 'towns': ['Freetown', 'Hill Station', 'Aberdeen']},
        {'region': 'Southern Province', 'district': 'Bo', 'towns': ['Bo']},
      ],
  'messaging:getMyConversations': (_) => [
        _conversation('req_1', 'seller'),
        _conversation('req_2', 'buyer', unread: 0),
        _conversation('req_3', 'seller', status: 'declined', unread: 0),
      ],
  'messaging:getThread': (a) => {
        'conversation': _conversation(a['requestId'] as String? ?? 'req_1', 'seller'),
        'canSend': true,
        'truncated': false,
        'messages': [
          {'id': 'm1', 'fromMe': false, 'body': _longMessage, 'createdAt': _now - 2 * _day},
          {'id': 'm2', 'fromMe': true, 'body': 'Yes, it is available. Saturday at ten works — I will meet you at the gate.', 'createdAt': _now - _day, 'readAt': _now - _day},
          {'id': 'm3', 'fromMe': false, 'body': 'Thank you!', 'createdAt': _now - 60000},
        ],
      },
  'messaging:markThreadRead': (_) => null,
  'bookings:getVendorBookings': (_) => [
        {..._booking(4, 'confirmed', 'held'), 'bookingType': 'property_inspection', 'buyerPhone': '+23276123456'},
        _booking(5, 'pending_payment', 'held'),
        _booking(6, 'cancelled', 'refunded'),
        _booking(-3, 'completed', 'released'),
      ],
};

const _longMessage =
    'Good afternoon, is the five bedroom villa still available for viewing this Saturday morning around ten? My family would like to see the garden and the boys quarters.';

Map<String, dynamic> _conversation(String id, String role, {String status = 'pending', int unread = 2}) => {
      'id': id,
      'myRole': role,
      'status': status,
      'counterpart': {
        'id': role == 'seller' ? 'user_1' : 'owner_1',
        'name': role == 'seller' ? _buyer.name : _longName,
        'avatarUrl': null,
        'isVerified': true,
      },
      'listingId': 'prop_0',
      'listingType': 'property',
      'listing': {
        'id': 'prop_0', 'type': 'property', 'title': '$_longTitle #0', 'category': 'sale', 'price': 1250000000,
        'currency': 'SLE', 'imageUrl': null, 'location': 'Inside Hill Station, Sierra Leone',
      },
      'lastMessage': _longMessage,
      'lastMessageAt': _now - 3600000,
      'lastMessageFromMe': role == 'buyer',
      'unread': unread,
      'createdAt': _now - _day,
    };

/// An agent page as the workspace pushes it (scope + workspace data loaded from the fake backend).
Widget _agentPage(ConvexClientWrapper c, Widget page) => AgentShellScope(
      user: _seller,
      convexClient: c,
      openTab: (_) {},
      openClientView: () {},
      child: BlocProvider(
        create: (_) => AgentWorkspaceCubit(
          api: AgentApi(client: c, userId: _seller.id, sessionToken: _seller.sessionToken),
          status: ProfessionalStatus.fromMap(const {'role': 'real_estate_agent', 'roleApproved': true, 'hasActiveSubscription': true, 'canPostProperty': true, 'verifiedAgent': true}),
        )..loadAll(),
        child: page,
      ),
    );

MessagingApi _messaging(ConvexClientWrapper c) => MessagingApi(client: c, userId: _buyer.id, sessionToken: _buyer.sessionToken);

ConvexClientWrapper _client() => ConvexClientWrapper(
      deploymentUrl: 'https://example.invalid',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final route = _routes[body['path']];
        final value = route == null ? null : route(Map<String, dynamic>.from(body['args'] as Map));
        return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
      }),
    );

final _entity = PropertyListingEntity(
  id: 'prop_1',
  ownerId: 'owner_1',
  title: '$_longTitle #1',
  description: 'Spacious villa with a large garden.',
  category: RealEstateCategory.fromString('long_term_rent'),
  price: 36000000,
  address: 'Inside Hill Station, Sierra Leone',
  city: 'Hill Station',
  country: 'Sierra Leone',
  latitude: 8.484,
  longitude: -13.234,
  geohash: '',
  availabilityStatus: 'available',
  ownerName: _longName,
  bedrooms: 5,
  bathrooms: 4,
  areaSqM: 1250,
);

/// (name, signed-in user, screen)
final _screens = <(String, UserEntity, Widget Function(ConvexClientWrapper c))>[
  ('Home', _buyer, (c) => ClientHomeScreen(convexClient: c)),
  ('Explore', _buyer, (c) => ExploreScreen(convexClient: c)),
  ('Buyer tab shell', _buyer, (c) => const MainNavigationShell()),
  ('Agent workspace (approved agent)', _seller, (c) => const MainNavigationShell()),
  ('Agent listings', _seller, (c) => _agentPage(c, const AgentListingsScreen())),
  ('Agent messages', _seller, (c) => _agentPage(c, const AgentMessagesScreen())),
  ('Agent notifications', _seller, (c) => _agentPage(c, const AgentNotificationsScreen())),
  ('Agent profile', _seller, (c) => _agentPage(c, const AgentProfileScreen())),
  ('Agent viewing requests', _seller, (c) => _agentPage(c, const AgentViewingsScreen())),
  ('Agent add property', _seller, (c) => _agentPage(c, const AgentAddListingScreen())),
  ('Messages inbox', _buyer, (c) => MessagesInboxScreen(api: _messaging(c))),
  ('Conversation', _buyer, (c) => ConversationScreen(api: _messaging(c), conversationId: 'req_1', refreshEvery: Duration.zero)),
  ('Login', _buyer, (c) => const LoginScreen()),
  ('Register', _buyer, (c) => const RegisterScreen()),
  ('Forgot password', _buyer, (c) => const ForgotPasswordScreen()),
  ('Complete profile (phone)', _buyer, (c) => const CompleteProfilePhoneScreen(user: _buyer)),
  ('Pending business verification', _pendingBusiness, (c) => const PendingVerificationScreen(user: _pendingBusiness)),
  ('Real Estate marketplace', _buyer, (c) => RealEstateMarketplaceScreen(convexClient: c)),
  ('Auto Market', _buyer, (c) => AutoMarketplaceScreen(convexClient: c)),
  ('Account (buyer)', _buyer, (c) => const ProfileScreen(currentUserId: 'user_1', showBackButton: false)),
  ('Account (seller)', _seller, (c) => const ProfileScreen(currentUserId: 'owner_1', showBackButton: false)),
  ('Notifications', _buyer, (c) => NotificationsScreen(convexClient: c, currentUserId: 'user_1')),
  ('My bookings', _buyer, (c) => MyBookingsScreen(convexClient: c, currentUser: _buyer)),
  ('My listings', _seller, (c) => MyListingsScreen(convexClient: c, currentUser: _seller)),
  ('Create listing', _seller, (c) => CreateListingScreen(convexClient: c, currentUser: _seller)),
  ('Public profile', _buyer, (c) => PublicProfileScreen(userId: 'owner_1', convexClient: c)),
  ('Social feed', _buyer, (c) => SocialFeedScreen(convexClient: c)),
  ('Discovery feed', _buyer, (c) => DiscoveryFeedScreen(convexClient: c)),
  ('Professional subscription', _seller, (c) => const ProfessionalSubscriptionScreen()),
  ('Real estate escrows', _buyer, (c) => const MyRealEstateEscrowsScreen()),
  ('Vehicle escrow orders', _buyer, (c) => const MyEscrowOrdersScreen()),
  ('Transaction history', _buyer, (c) => TransactionHistoryScreen(convexClient: c)),
  (
    'Transaction receipt',
    _buyer,
    (c) => TransactionReceiptScreen(
          transactionId: 'VX-TXN-0000001234567',
          amount: 125000750.55,
          feeAmount: 1250007.5,
          netAmount: 123750743.05,
          currency: 'SLE',
          timestamp: DateTime(2026, 10, 3, 14, 30),
          type: 'p2p_transfer',
          status: 'COMPLETED',
          senderName: _buyer.name,
          senderPhone: _buyer.phone,
          recipientName: _longName,
          recipientPhone: '+23277987654',
          updatedBalance: 1250007.5,
          note: 'Deposit for the long-term lease of the five bedroom villa at Hill Station',
        ),
  ),
  (
    'Property detail',
    _buyer,
    (c) => PropertyDetailScreen(
          id: 'prop_0',
          title: '$_longTitle #0',
          description: 'Spacious villa with a large garden, boys quarters, 24/7 water supply and secure parking.',
          category: 'sale',
          price: 1250000000,
          address: 'Inside Hill Station, Sierra Leone',
          latitude: 8.484,
          longitude: -13.234,
          ownerId: 'owner_1',
          ownerName: _longName,
          bedrooms: 5,
          bathrooms: 4,
          squareMeters: 1250,
          isVerified: true,
          amenities: const ['Parking', 'Generator / backup power', '24/7 Security', 'Water supply', 'Swimming pool'],
        ),
  ),
  (
    'Vehicle detail',
    _buyer,
    (c) => const VehicleDetailScreen(
          id: 'veh_0',
          make: 'Toyota',
          model: 'Land Cruiser Prado VX Limited',
          year: 2023,
          vehicleType: 'car_sale',
          listingIntent: 'sale',
          salePrice: 985000000,
          ownerId: 'owner_1',
          ownerName: _longName,
          color: 'Pearl White Metallic',
          transmission: 'Automatic',
          fuelType: 'Diesel',
          mileage: '125,000 km',
          location: 'Inside Freetown, Sierra Leone',
        ),
  ),
  (
    'Booking checkout',
    _buyer,
    (c) => CheckoutScreen(
          convexClient: c,
          currentUser: _buyer,
          listingId: 'prop_2',
          listingType: 'property',
          listingTitle: '$_longTitle #2',
          listingSubtitle: 'Inside Hill Station, Sierra Leone',
          vendorId: 'owner_1',
          bookingType: 'instant_stay',
          startTime: _now + _day,
          endTime: _now + 3 * _day,
          days: 2,
          subtotal: 1500000,
          serviceFee: 75000,
          totalAmount: 1575000,
        ),
  ),
  (
    'Vehicle escrow checkout',
    _buyer,
    (c) => const EscrowCheckoutScreen(
          vehicleListingId: 'veh_1',
          vehicleTitle: '2023 Toyota Land Cruiser Prado VX Limited Edition',
          vehicleCategory: 'car_rental',
          dailyRate: 25000,
        ),
  ),
  (
    'Real estate escrow checkout',
    _buyer,
    (c) => RealEstateEscrowCheckoutScreen(listing: _entity, initialType: RealEstateEscrowType.longTermLease),
  ),
  (
    'Delivery van booking',
    _buyer,
    (c) => DeliveryVanBookingScreen(vehicle: _vehicle(2, category: 'delivery_van', pricingType: 'per_trip'), convexClient: c),
  ),
  ('Operator dashboard', _seller, (c) => OperatorDashboardScreen(convexClient: c)),
  ('Identity verification', _buyer, (c) => IdentityVerificationScreen(convexClient: c, currentUser: _buyer, onVerificationComplete: () {})),
  ('Agent verification', _seller, (c) => AgentVerificationScreen(convexClient: c, currentUser: _seller)),
  ('Inspection pass verification', _seller, (c) => const InspectionPassVerificationScreen()),
];

// ─── Harness ─────────────────────────────────────────────────────────────

final List<String> _errors = [];

Future<void> _pump(WidgetTester tester, _Device d, UserEntity user, Widget Function(ConvexClientWrapper) build) async {
  _errors.clear();
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _errors.add(details.toString());
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = Size(d.width * 3, d.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = d.textScale;
  final client = _client();
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: AuthState(status: AuthStatus.authenticated, user: user));
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ConvexClientWrapper>.value(value: client),
        RepositoryProvider<AuthRepository>(create: (_) => AuthRepositoryImpl(convexClient: client)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: bloc),
          BlocProvider<WalletCubit>(create: (_) => WalletCubit(convexClient: client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => AppTextScale(child: child ?? const SizedBox.shrink()),
          home: build(client),
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _scrollThrough(tester);
}

/// Scrolls every vertical list to its end so lazily built rows are laid out (and checked) too.
Future<void> _scrollThrough(WidgetTester tester) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  final count = vertical.evaluate().length;
  for (var s = 0; s < count && s < 6; s++) {
    for (var step = 0; step < 12; step++) {
      final all = vertical.evaluate().toList();
      if (s >= all.length) break;
      final position = (all[s] as StatefulElement).state is ScrollableState
          ? ((all[s] as StatefulElement).state as ScrollableState).position
          : null;
      if (position == null || !position.hasContentDimensions || position.pixels >= position.maxScrollExtent - 1) break;
      position.jumpTo(math.min(position.pixels + 450, position.maxScrollExtent));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

/// The app names Poppins / Inter (not bundled), so phones use their system font. Measure with
/// Roboto (close to the Android / iOS system fonts) under every family name the app uses.
Future<void> _loadFonts() async {
  Directory? dir;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) dir = Directory('$root/bin/cache/artifacts/material_fonts');
  var cur = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8 && (dir == null || !dir.existsSync()); i++) {
    final candidate = Directory('${cur.path}/bin/cache/artifacts/material_fonts');
    if (candidate.existsSync()) dir = candidate;
    cur = cur.parent;
  }
  if (dir == null || !dir.existsSync()) return;
  for (final family in ['Roboto', 'Inter', 'Poppins', 'Courier', 'monospace']) {
    final loader = FontLoader(family);
    for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
      final file = File('${dir.path}/$f');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final (name, user, build) in _screens) {
    group(name, () {
      for (final d in _devices) {
        testWidgets('fits a ${d.name}', (tester) async {
          await _pump(tester, d, user, build);
          tester.takeException();
          final errors = List<String>.from(_errors);
          await _tearDown(tester);
          if (errors.isNotEmpty) fail(errors.join('\n----\n'));
        });
      }
    });
  }
}
