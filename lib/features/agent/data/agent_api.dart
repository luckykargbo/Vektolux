// lib/features/agent/data/agent_api.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent workspace: calls to EXISTING Convex functions.
//
// A thin typed layer over ConvexClientWrapper (no second data source, no new backend API).
// Identity is always the session: every private query/mutation is authorised server-side by
// `sessionToken`; the user id passed alongside is only checked against it by the server.
// A failed call throws [AgentApiException] with the server's message — callers show it as a
// recoverable error and never substitute placeholder data.
// ═══════════════════════════════════════════════════════════════════════

import '../../../core/network/convex_client_wrapper.dart';
import '../domain/agent_models.dart';

class AgentApiException implements Exception {
  final String message;
  const AgentApiException(this.message);

  @override
  String toString() => message;
}

/// Outcome of accepting / declining a buyer inquiry, as reported by the server.
class InquiryResponseResult {
  final String status;
  final String message;
  const InquiryResponseResult({required this.status, required this.message});
}

/// Fields the agent enters in the Add Listing flow (validated again by the server).
class NewPropertyListing {
  final String title;
  final String description;
  final String category;
  final double price;
  final double? hourlyRate;
  final String privateAddress;
  final String? town;
  final String? district;
  final int? bedrooms;
  final int? bathrooms;
  final double? areaSqM;
  final List<String> amenities;
  final List<String> imageStorageIds;
  final bool publish;

  const NewPropertyListing({
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    this.hourlyRate,
    required this.privateAddress,
    this.town,
    this.district,
    this.bedrooms,
    this.bathrooms,
    this.areaSqM,
    this.amenities = const [],
    this.imageStorageIds = const [],
    this.publish = true,
  });
}

class AgentApi {
  final ConvexClientWrapper client;
  final String userId;
  final String? sessionToken;

  const AgentApi({required this.client, required this.userId, this.sessionToken});

  Map<String, dynamic> _session([Map<String, dynamic> args = const {}]) => {
        ...args,
        if (sessionToken != null && sessionToken!.isNotEmpty) 'sessionToken': sessionToken,
      };

  Future<dynamic> _query(String path, Map<String, dynamic> args) async {
    final res = await client.query(path, args: args);
    if (!res.success) throw AgentApiException(res.errorMessage ?? 'The server could not load this information.');
    return res.value;
  }

  Future<dynamic> _mutation(String path, Map<String, dynamic> args) async {
    final res = await client.mutation(path, args: args);
    if (!res.success) throw AgentApiException(res.errorMessage ?? 'The server could not complete this action.');
    return res.value;
  }

  // ─── Role, approval & subscription ───────────────────────────────────

  Future<ProfessionalStatus?> professionalStatus() async {
    final v = await _query('subscriptions:getMyProfessionalStatus', _session());
    return v is Map ? ProfessionalStatus.fromMap(Map<String, dynamic>.from(v)) : null;
  }

  Future<SubscriptionInfo?> activeSubscription() async {
    final v = await _query('subscriptions:getUserActiveSubscription', _session());
    return v is Map ? SubscriptionInfo.fromMap(Map<String, dynamic>.from(v)) : null;
  }

  // ─── Listings ─────────────────────────────────────────────────────────

  /// The agent's own property listings (deleted ones are excluded by the server).
  Future<List<AgentListing>> myListings() async {
    final v = await _query('realEstate:getMyPropertyListings', _session({'ownerId': userId}));
    return mapList(v).map(AgentListing.fromOwn).where((l) => l.id.isNotEmpty).toList();
  }

  /// Public, privacy-safe view of any listing (no street address, coordinates or private phone).
  Future<Map<String, dynamic>?> publicProperty(String listingId) async {
    final v = await _query('realEstate:getPropertyById', {'listingId': listingId});
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<List<AgentAuthorization>> myAuthorizations() async {
    final v = await _query('listingAgents:getMyAgentAuthorizations', _session());
    return mapList(v).map(AgentAuthorization.fromMap).toList();
  }

  Future<void> respondToInvitation(String authorizationId, {required bool accept}) async {
    await _mutation('listingAgents:respondToListingAgentInvitation',
        _session({'authorizationId': authorizationId, 'accept': accept}));
  }

  /// The agent withdraws from representing a listing (the owner is notified by the server).
  Future<void> stopRepresenting(String authorizationId, String reason) async {
    await _mutation('listingAgents:revokeListingAgent', _session({'authorizationId': authorizationId, 'reason': reason}));
  }

  /// Publishing re-checks the posting permission on the server; unpublishing hides the listing.
  Future<void> setPublished(String listingId, bool publish) async {
    await _mutation('realEstate:updatePropertyListing',
        _session({'listingId': listingId, 'ownerId': userId, 'isPublished': publish}));
  }

  Future<void> updateListingDetails(
    String listingId, {
    String? title,
    String? description,
    double? price,
    int? bedrooms,
    int? bathrooms,
  }) async {
    await _mutation('realEstate:updatePropertyListing', _session({
      'listingId': listingId,
      'ownerId': userId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (price != null) 'price': price,
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (bathrooms != null) 'bathrooms': bathrooms,
    }));
  }

  Future<void> deleteListing(String listingId) async {
    await _mutation('realEstate:deletePropertyListing', _session({'listingId': listingId, 'ownerId': userId}));
  }

  /// Creates the listing through the existing mutation (server enforces role approval +
  /// subscription via postingPermission). Returns the new listing id.
  Future<String> createListing(NewPropertyListing l) async {
    final v = await _mutation('realEstate:createPropertyListing', _session({
      'ownerId': userId,
      'title': l.title,
      'description': l.description,
      'category': l.category,
      'price': l.price,
      if (l.hourlyRate != null) 'hourlyRate': l.hourlyRate,
      'currency': 'SLE',
      'address': l.privateAddress,
      'city': l.town ?? l.district ?? '',
      if (l.district != null) 'district': l.district,
      'country': 'Sierra Leone',
      'imageStorageIds': l.imageStorageIds,
      if (l.bedrooms != null) 'bedrooms': l.bedrooms,
      if (l.bathrooms != null) 'bathrooms': l.bathrooms,
      if (l.areaSqM != null) 'areaSqM': l.areaSqM,
      if (l.amenities.isNotEmpty) 'amenities': l.amenities,
      'isPublished': l.publish,
    }));
    return v?.toString() ?? '';
  }

  // ─── Messages (buyer inquiries) ──────────────────────────────────────

  Future<List<Inquiry>> inquiries() async {
    final v = await _query('adminPortal:getSellerContactRequests', _session({'sellerId': userId}));
    return mapList(v).map(Inquiry.fromMap).toList();
  }

  /// Accepting shares the agent's OWN phone number with that buyer (server behaviour).
  Future<InquiryResponseResult> respondToInquiry(String requestId, {required bool accept}) async {
    final v = await _mutation('adminPortal:respondToContactRequest',
        _session({'sellerId': userId, 'requestId': requestId, 'action': accept ? 'accepted' : 'declined'}));
    final m = v is Map ? v : const {};
    return InquiryResponseResult(
      status: m['status']?.toString() ?? (accept ? 'ACCEPTED' : 'DECLINED'),
      message: m['message']?.toString() ?? '',
    );
  }

  // ─── Notifications ───────────────────────────────────────────────────

  Future<List<AgentNotification>> notifications({int limit = 50}) async {
    final v = await _query('notifications:getUserNotifications', _session({'userId': userId, 'limit': limit}));
    return mapList(v).map(AgentNotification.fromMap).toList();
  }

  Future<int> unreadNotificationCount() async {
    final v = await _query('notifications:getUnreadNotificationCount', _session({'userId': userId}));
    return v is num ? v.toInt() : 0;
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _mutation('notifications:markAsRead', _session({'notificationId': notificationId, 'userId': userId}));
  }

  Future<void> markAllNotificationsRead() async {
    await _mutation('notifications:markAllAsRead', _session({'userId': userId}));
  }

  // ─── Profile & social graph ──────────────────────────────────────────

  Future<ProfileCounts?> profileCounts() async {
    final v = await _query('users:getUserProfile', _session({'userId': userId}));
    return v is Map ? ProfileCounts.fromMap(Map<String, dynamic>.from(v)) : null;
  }

  Future<List<PersonSummary>> followers() async =>
      mapList(await _query('social:getFollowersList', {'userId': userId})).map(PersonSummary.fromMap).toList();

  Future<List<PersonSummary>> following() async =>
      mapList(await _query('social:getFollowingList', {'userId': userId})).map(PersonSummary.fromMap).toList();

  // ─── Deals, earnings & payouts (read-only) ───────────────────────────

  /// Raw `realEstateEscrow:getMyRealEstateEscrows` response (contracts + inspection passes).
  Future<dynamic> realEstateEscrows() => _query('realEstateEscrow:getMyRealEstateEscrows', _session({'userId': userId}));

  Future<EarningsSummary> earningsSummary() async {
    final v = await _query('walletCore:getEarningsSummary', _session());
    return EarningsSummary.fromMap(v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
  }

  Future<WalletBalance> walletBalance() async {
    final v = await _query('wallet:getUserBalance', _session({'userId': userId}));
    if (v is! Map) throw const AgentApiException('Wallet balance is unavailable.');
    return WalletBalance.fromMap(Map<String, dynamic>.from(v));
  }

  Future<List<WithdrawalRecord>> withdrawals() async =>
      mapList(await _query('withdrawals:getMyWithdrawals', _session())).map(WithdrawalRecord.fromMap).toList();
}
