// lib/features/agent/domain/agent_models.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent workspace: data models and display rules.
//
// Everything here is parsed from Convex responses; nothing is invented. Permissions (role
// approval, subscription, posting) are decided by the server — these types only describe the
// server's answer so the app can choose which screens to show.
// ═══════════════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';

// ─── Parsing helpers (tolerant of missing / wrongly typed fields) ─────

String _str(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();
String? _optStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

bool _bool(dynamic v) => v == true;
int? _optInt(dynamic v) => v is num ? v.toInt() : null;
double? _optDouble(dynamic v) => v is num ? v.toDouble() : null;
int _int(dynamic v) => v is num ? v.toInt() : 0;
double _double(dynamic v) => v is num ? v.toDouble() : 0;

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};

List<Map<String, dynamic>> mapList(dynamic v) =>
    v is List ? v.whereType<Map>().map(_map).toList() : <Map<String, dynamic>>[];

// ═══════════════════════════════════════════════════════════════════════
//                     ROLE, APPROVAL & SUBSCRIPTION
// ═══════════════════════════════════════════════════════════════════════

/// Which experience the signed-in account gets. Chosen from the server's professional status;
/// choosing it never grants a permission (every action is re-checked by the server).
enum AgentAccess {
  /// Not a Real Estate Agent (client/buyer, real estate owner, dealer, hotel owner, admin).
  none,

  /// An administrator-approved Real Estate Agent: the agent workspace.
  approved,

  /// Registered as, or applied to be, a Real Estate Agent but not approved (yet).
  awaitingApproval,
}

class RoleApplication {
  final String id;
  final String targetRole;

  /// pending | approved | rejected | suspended (as stored by the server).
  final String status;
  final String? reviewNotes;

  const RoleApplication({
    required this.id,
    required this.targetRole,
    required this.status,
    this.reviewNotes,
  });

  factory RoleApplication.fromMap(Map<String, dynamic> m) => RoleApplication(
        id: _str(m['id']),
        targetRole: _str(m['targetRole']),
        status: _str(m['status']),
        reviewNotes: _optStr(m['reviewNotes']),
      );
}

/// What the account is allowed to be RIGHT NOW, as the server decided it from stored admin approvals
/// (`capabilities` in `subscriptions:getMyProfessionalStatus`). Several can be true at once (e.g.
/// Real Estate Agent + Car Dealer). A subscription never changes them; it only gates posting.
class ProfessionalCapabilities {
  final bool realEstateAgent;
  final bool realEstateOwner;
  final bool hotelOperator;
  final bool carDealer;
  final bool admin;

  const ProfessionalCapabilities({
    this.realEstateAgent = false,
    this.realEstateOwner = false,
    this.hotelOperator = false,
    this.carDealer = false,
    this.admin = false,
  });

  factory ProfessionalCapabilities.fromMap(Map<String, dynamic> m) => ProfessionalCapabilities(
        realEstateAgent: _bool(m['realEstateAgent']),
        realEstateOwner: _bool(m['realEstateOwner']),
        hotelOperator: _bool(m['hotelOperator']),
        carDealer: _bool(m['carDealer']),
        admin: _bool(m['admin']),
      );
}

/// `subscriptions:getMyProfessionalStatus` — the server's view of the caller's business role.
class ProfessionalStatus {
  /// Business role: client | real_estate_agent | real_estate_owner | vehicle_dealer | hotel_owner | admin.
  final String role;
  final bool roleApproved;

  /// Computed badge: approved agent with an active paid subscription.
  final bool verifiedAgent;
  final int? agentExpiresAt;
  final bool hasActiveSubscription;
  final bool isInGracePeriod;
  final int? gracePeriodEndsAt;
  final int? legacyGraceEndedAt;
  final bool canPostProperty;

  /// Car Dealer is a SEPARATE, admin-approved authorisation held next to the agent role. Only the
  /// server sets these; they decide whether the Auto tools are offered at all.
  final bool isCarDealer;
  final bool canPostVehicle;
  final String? _professionalTitle;

  /// Newest first (as returned by the server).
  final List<RoleApplication> applications;

  /// Null when the connected server does not send capabilities yet (older backend).
  final ProfessionalCapabilities? capabilities;

  const ProfessionalStatus({
    required this.role,
    required this.roleApproved,
    this.verifiedAgent = false,
    this.agentExpiresAt,
    this.hasActiveSubscription = false,
    this.isInGracePeriod = false,
    this.gracePeriodEndsAt,
    this.legacyGraceEndedAt,
    this.canPostProperty = false,
    this.isCarDealer = false,
    this.canPostVehicle = false,
    String? professionalTitle,
    this.applications = const [],
    this.capabilities,
  }) : _professionalTitle = professionalTitle;

  factory ProfessionalStatus.fromMap(Map<String, dynamic> m) => ProfessionalStatus(
        role: _str(m['role'], 'client'),
        roleApproved: _bool(m['roleApproved']),
        verifiedAgent: _bool(m['verifiedAgent']),
        agentExpiresAt: _optInt(m['agentExpiresAt']),
        hasActiveSubscription: _bool(m['hasActiveSubscription']),
        isInGracePeriod: _bool(m['isInGracePeriod']),
        gracePeriodEndsAt: _optInt(m['gracePeriodEndsAt']),
        legacyGraceEndedAt: _optInt(m['legacyGraceEndedAt']),
        canPostProperty: _bool(m['canPostProperty']),
        isCarDealer: _bool(m['isCarDealer']),
        canPostVehicle: _bool(m['canPostVehicle']),
        professionalTitle: _optStr(m['professionalTitle']),
        applications: mapList(m['applications']).map(RoleApplication.fromMap).toList(),
        capabilities: m['capabilities'] is Map
            ? ProfessionalCapabilities.fromMap(Map<String, dynamic>.from(m['capabilities'] as Map))
            : null,
      );

  bool get isRealEstateAgent => role == 'real_estate_agent';

  /// "Real Estate Agent" or "Real Estate Agent & Car Dealer" (the server's wording).
  String get professionalTitle => _professionalTitle ?? (isCarDealer ? 'Real Estate Agent & Car Dealer' : 'Real Estate Agent');

  /// The Auto tools (add / manage vehicles) are offered only to an approved Car Dealer.
  bool get showAutoTools => isCarDealer && canPostVehicle;

  /// The newest application for the Real Estate Agent role, if any.
  RoleApplication? get latestAgentApplication {
    for (final a in applications) {
      if (a.targetRole == 'agent') return a;
    }
    return null;
  }

  AgentAccess get access {
    if (isRealEstateAgent) {
      // The server's capability is authoritative when it is sent (an older server: role + approval).
      final approved = capabilities?.realEstateAgent ?? roleApproved;
      return approved ? AgentAccess.approved : AgentAccess.awaitingApproval;
    }
    // A client whose agent application is under review sees its status (a suspended or rejected
    // agent is a client again and keeps the standard app).
    if (role == 'client' && latestAgentApplication?.status == 'pending') {
      return AgentAccess.awaitingApproval;
    }
    return AgentAccess.none;
  }

  /// Why the server would refuse a new listing right now (null when it allows it).
  String? get postingBlockedReason {
    if (canPostProperty) return null;
    if (!roleApproved) return 'Your Real Estate Agent account is awaiting approval.';
    if (legacyGraceEndedAt != null) {
      return 'Your legacy-agent grace period ended on ${formatDate(legacyGraceEndedAt!)}. '
          'Subscribe to keep posting listings.';
    }
    return 'Your Real Estate Agent subscription is not active. Subscribe to post listings.';
  }
}

/// `subscriptions:getUserActiveSubscription` (only the fields the agent screens show).
class SubscriptionInfo {
  final String planName;
  final String status;
  final int expiryDate;

  const SubscriptionInfo({required this.planName, required this.status, required this.expiryDate});

  factory SubscriptionInfo.fromMap(Map<String, dynamic> m) => SubscriptionInfo(
        planName: _str(m['planName'], _str(m['tierCode'])),
        status: _str(m['status']),
        expiryDate: _int(m['expiryDate']),
      );

  bool isActiveAt(DateTime now) => status == 'active' && expiryDate > now.millisecondsSinceEpoch;
}

/// Label for the professional subscription, shown only when the server reports an active one.
String? subscriptionLabel(ProfessionalStatus status, SubscriptionInfo? sub, {DateTime? now}) {
  if (!status.hasActiveSubscription) {
    return status.isInGracePeriod && status.gracePeriodEndsAt != null
        ? 'Grace period until ${formatDate(status.gracePeriodEndsAt!)}'
        : null;
  }
  if (sub != null && sub.isActiveAt(now ?? DateTime.now()) && sub.planName.trim().isNotEmpty) {
    return sub.planName.trim();
  }
  return 'Active subscription';
}

// ═══════════════════════════════════════════════════════════════════════
//                               LISTINGS
// ═══════════════════════════════════════════════════════════════════════

/// A listing's state as its owner sees it. The SERVER derives it (`lifecycleStatus`); the app never
/// decides that a listing is approved or live.
enum ListingStatus { active, offMarket, pendingReview, rejected, removed, draft, unpublished, archived }

extension ListingStatusX on ListingStatus {
  String get label => switch (this) {
        ListingStatus.active => 'Active',
        ListingStatus.offMarket => 'Off-market',
        ListingStatus.pendingReview => 'Pending review',
        ListingStatus.rejected => 'Rejected',
        ListingStatus.removed => 'Removed',
        ListingStatus.draft => 'Draft',
        ListingStatus.unpublished => 'Unpublished',
        ListingStatus.archived => 'Archived',
      };

  /// Anyone can see it on the marketplace.
  bool get isPublic => this == ListingStatus.active || this == ListingStatus.offMarket;

  static ListingStatus? fromServer(String? v) => switch (v) {
        'active' => ListingStatus.active,
        'off_market' => ListingStatus.offMarket,
        'pending_review' => ListingStatus.pendingReview,
        'rejected' => ListingStatus.rejected,
        'removed' => ListingStatus.removed,
        'draft' => ListingStatus.draft,
        'unpublished' => ListingStatus.unpublished,
        'archived' => ListingStatus.archived,
        _ => null,
      };
}

/// Listing filters. Status filters come from the listings' real states; only filters that apply to
/// the agent's portfolio are shown (see [visibleFilters]).
enum ListingFilter { all, active, pendingReview, rejected, unpublished, offMarket, archived, removed, sale, rent }

extension ListingFilterX on ListingFilter {
  String get label => switch (this) {
        ListingFilter.all => 'All',
        ListingFilter.active => 'Active',
        ListingFilter.pendingReview => 'Pending review',
        ListingFilter.rejected => 'Rejected',
        ListingFilter.unpublished => 'Unpublished',
        ListingFilter.offMarket => 'Off-market',
        ListingFilter.archived => 'Archived',
        ListingFilter.removed => 'Removed',
        ListingFilter.sale => 'For Sale',
        ListingFilter.rent => 'For Rent',
      };
}

/// A property in the agent's portfolio: either their own listing, or a listing whose owner
/// authorised them to represent it (read-only for the agent; the owner keeps control).
class AgentListing {
  final String id;
  final String title;
  final String description;

  /// The listing's owner (the agent for their own listings; the owner for represented ones).
  final String ownerId;

  /// sale | long_term_rent | hourly_guesthouse
  final String category;
  final double price;
  final double? hourlyRate;
  final String currency;

  /// Broad public place (town / district). Never the street address.
  final String? town;
  final String? district;
  final String? publicLocationText;
  final int? bedrooms;
  final int? bathrooms;
  final double? areaSqM;
  final List<String> amenities;
  final List<String> imageUrls;

  /// Public property videos (real uploaded files).
  final List<String> videoUrls;
  final String availabilityStatus;
  final bool isPublished;
  final int createdAt;
  final int updatedAt;

  /// The server-derived lifecycle state (active, pending review, rejected, …).
  final ListingStatus status;

  /// Why an administrator rejected / removed the listing (only the owner receives it).
  final String? moderationReason;

  /// Real, server-maintained statistics; null when the server did not report them (for example
  /// for a listing the agent only represents).
  final int? viewCount;
  final int? saveCount;
  final int? inquiryCount;
  final int? viewingRequestCount;

  /// Set when the agent represents this listing for its owner (not the agent's own listing).
  final String? representationId;

  const AgentListing({
    required this.id,
    required this.title,
    this.description = '',
    this.ownerId = '',
    required this.category,
    required this.price,
    this.hourlyRate,
    this.currency = 'SLE',
    this.town,
    this.district,
    this.publicLocationText,
    this.bedrooms,
    this.bathrooms,
    this.areaSqM,
    this.amenities = const [],
    this.imageUrls = const [],
    this.videoUrls = const [],
    this.availabilityStatus = 'available',
    this.isPublished = true,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.status = ListingStatus.active,
    this.moderationReason,
    this.viewCount,
    this.saveCount,
    this.inquiryCount,
    this.viewingRequestCount,
    this.representationId,
  });

  /// From `realEstate:getMyPropertyListings` (the caller's own listings). The private fields that
  /// query returns (street address, coordinates, contact phone) are deliberately NOT kept.
  factory AgentListing.fromOwn(Map<String, dynamic> m) => AgentListing(
        id: _str(m['_id']),
        title: _str(m['title'], 'Untitled listing'),
        description: _str(m['description']),
        ownerId: _str(m['ownerId']),
        category: _str(m['category']),
        price: _double(m['price']),
        hourlyRate: _optDouble(m['hourlyRate']),
        currency: _str(m['currency'], 'SLE'),
        town: _optStr(m['city']),
        district: _optStr(m['district']),
        bedrooms: _optInt(m['bedrooms']),
        bathrooms: _optInt(m['bathrooms']),
        areaSqM: _optDouble(m['areaSqM']),
        amenities: (m['amenities'] is List) ? (m['amenities'] as List).map((e) => e.toString()).toList() : const [],
        imageUrls: (m['imageUrls'] is List)
            ? (m['imageUrls'] as List).map((e) => e.toString()).where((u) => u.startsWith('http')).toList()
            : const [],
        videoUrls: (m['videoUrls'] is List)
            ? (m['videoUrls'] as List).map((e) => e.toString()).where((u) => u.startsWith('http')).toList()
            : const [],
        availabilityStatus: _str(m['availabilityStatus'], 'available'),
        isPublished: m['isPublished'] != false,
        createdAt: _int(m['_creationTime']),
        updatedAt: _int(m['updatedAt']),
        status: ListingStatusX.fromServer(_optStr(m['lifecycleStatus'])) ?? _statusFromFields(m),
        moderationReason: _optStr(m['moderationReason']),
        viewCount: _optInt(m['viewCount']),
        saveCount: _optInt(m['saveCount']),
        inquiryCount: _optInt(m['inquiryCount']),
        viewingRequestCount: _optInt(m['viewingRequestCount']),
      );

  /// From `realEstate:getPropertyById` (the public, privacy-safe view) for a listing the agent
  /// represents with the owner's authorisation.
  factory AgentListing.fromPublic(Map<String, dynamic> m, {required String representationId}) => AgentListing(
        id: _str(m['_id']),
        title: _str(m['title'], 'Untitled listing'),
        description: _str(m['description']),
        ownerId: _str(m['ownerId']),
        category: _str(m['category']),
        price: _double(m['price']),
        hourlyRate: _optDouble(m['hourlyRate']),
        currency: _str(m['currency'], 'SLE'),
        town: _optStr(m['city']),
        district: _optStr(m['district']),
        publicLocationText: _optStr(m['publicLocation']),
        bedrooms: _optInt(m['bedrooms']),
        bathrooms: _optInt(m['bathrooms']),
        areaSqM: _optDouble(m['areaSqM']),
        amenities: (m['amenities'] is List) ? (m['amenities'] as List).map((e) => e.toString()).toList() : const [],
        imageUrls: (m['imageUrls'] is List)
            ? (m['imageUrls'] as List).map((e) => e.toString()).where((u) => u.startsWith('http')).toList()
            : const [],
        videoUrls: (m['videoUrls'] is List)
            ? (m['videoUrls'] as List).map((e) => e.toString()).where((u) => u.startsWith('http')).toList()
            : const [],
        availabilityStatus: _str(m['availabilityStatus'], 'available'),
        isPublished: m['isPublished'] != false,
        createdAt: _int(m['_creationTime']),
        updatedAt: _int(m['updatedAt']),
        status: ListingStatusX.fromServer(_optStr(m['lifecycleStatus'])) ?? _statusFromFields(m),
        representationId: representationId,
      );

  /// Used only when a response carries no `lifecycleStatus`: the state its raw fields imply.
  static ListingStatus _statusFromFields(Map<String, dynamic> m) {
    switch (m['moderationStatus']) {
      case 'pending_review':
        return ListingStatus.pendingReview;
      case 'rejected':
        return ListingStatus.rejected;
      case 'removed':
        return ListingStatus.removed;
    }
    if (m['isPublished'] == false) return ListingStatus.unpublished;
    return _str(m['availabilityStatus'], 'available') == 'available' ? ListingStatus.active : ListingStatus.offMarket;
  }

  bool get isRepresented => representationId != null;
  bool get isForSale => category == 'sale';
  bool get isForRent => category == 'long_term_rent' || category == 'hourly_guesthouse';
  String? get coverImage => imageUrls.isEmpty ? null : imageUrls.first;

  /// "For Sale" / "For Rent" / "Short Stay" — null for an unknown category (no invented tag).
  String? get categoryLabel => switch (category) {
        'sale' => 'For Sale',
        'long_term_rent' => 'For Rent',
        'hourly_guesthouse' => 'Short Stay',
        _ => null,
      };

  /// Generalised public location: town and district only (e.g. "Aberdeen, Western Area Urban").
  String get publicLocation {
    final explicit = publicLocationText;
    if (explicit != null) return explicit;
    final parts = <String>[];
    for (final p in [town, district]) {
      if (p != null && p.isNotEmpty && !parts.any((x) => x.toLowerCase() == p.toLowerCase())) parts.add(p);
    }
    if (parts.isEmpty) return 'Sierra Leone';
    if (parts.length == 1) return '${parts.first}, Sierra Leone';
    return parts.join(', ');
  }

  String get priceLabel {
    final rate = hourlyRate;
    if (category == 'hourly_guesthouse' && rate != null && rate > 0) return '${formatMoney(rate, currency: currency)} / hr';
    if (price <= 0) return 'Price on request';
    if (category == 'long_term_rent') return '${formatMoney(price, currency: currency)} / year';
    return formatMoney(price, currency: currency);
  }

  bool matches(ListingFilter filter) => switch (filter) {
        ListingFilter.all => true,
        ListingFilter.active => status == ListingStatus.active,
        ListingFilter.pendingReview => status == ListingStatus.pendingReview,
        ListingFilter.rejected => status == ListingStatus.rejected,
        ListingFilter.unpublished => status == ListingStatus.draft || status == ListingStatus.unpublished,
        ListingFilter.offMarket => status == ListingStatus.offMarket,
        ListingFilter.archived => status == ListingStatus.archived,
        ListingFilter.removed => status == ListingStatus.removed,
        ListingFilter.sale => isForSale,
        ListingFilter.rent => isForRent,
      };

  /// What the owner may do next (the server re-checks every action).
  bool get canSubmitForReview => !isRepresented && (status == ListingStatus.draft || status == ListingStatus.unpublished);
  bool get canWithdraw => !isRepresented && status == ListingStatus.pendingReview;
  bool get canResubmit => !isRepresented && status == ListingStatus.rejected;
  bool get canUnpublish => !isRepresented && status.isPublic;
  bool get canArchive =>
      !isRepresented && status != ListingStatus.archived && status != ListingStatus.removed;
  bool get canRestore => !isRepresented && status == ListingStatus.archived;
  bool get canEdit => !isRepresented && status != ListingStatus.removed && status != ListingStatus.archived;

  bool get hasVideo => videoUrls.isNotEmpty;
}

int countMatching(Iterable<AgentListing> listings, ListingFilter filter) =>
    listings.where((l) => l.matches(filter)).length;

/// The filters worth showing for this portfolio: All, plus every status (or sale / rent) that
/// applies to some — but not all — of the listings. The selected filter always stays visible.
List<ListingFilter> visibleFilters(List<AgentListing> listings, {ListingFilter selected = ListingFilter.all}) {
  final total = listings.length;
  return [
    for (final f in ListingFilter.values)
      if (f == ListingFilter.all || f == selected || (countMatching(listings, f) > 0 && countMatching(listings, f) < total)) f,
  ];
}

/// Newest first (creation time, then last update).
List<AgentListing> newestFirst(Iterable<AgentListing> listings) {
  final list = listings.toList();
  list.sort((a, b) {
    final c = b.createdAt.compareTo(a.createdAt);
    return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
  });
  return list;
}

/// `listingAgents` authorisation row (owner → agent, per listing).
class AgentAuthorization {
  final String id;
  final String listingType;
  final String listingId;

  /// pending | active | declined | revoked
  final String status;
  final int invitedAt;
  final int? acceptedAt;

  const AgentAuthorization({
    required this.id,
    required this.listingType,
    required this.listingId,
    required this.status,
    required this.invitedAt,
    this.acceptedAt,
  });

  factory AgentAuthorization.fromMap(Map<String, dynamic> m) => AgentAuthorization(
        id: _str(m['id']),
        listingType: _str(m['listingType']),
        listingId: _str(m['listingId']),
        status: _str(m['status']),
        invitedAt: _int(m['invitedAt']),
        acceptedAt: _optInt(m['acceptedAt']),
      );

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isProperty => listingType == 'property';
}

/// A pending invitation together with the public view of the listing (null if it could not load).
class AgentInvitation {
  final AgentAuthorization authorization;
  final AgentListing? listing;
  const AgentInvitation(this.authorization, this.listing);
}

// ═══════════════════════════════════════════════════════════════════════
//                     VIEWING REQUESTS (site visits & stays)
// ═══════════════════════════════════════════════════════════════════════

enum ViewingTab { pending, confirmed, declined, cancelled }

extension ViewingTabX on ViewingTab {
  String get label => switch (this) {
        ViewingTab.pending => 'Pending',
        ViewingTab.confirmed => 'Confirmed',
        ViewingTab.declined => 'Declined',
        ViewingTab.cancelled => 'Cancelled',
      };
}

/// A free site-visit request on a listing the caller manages (`bookings:getMyViewingRequests`).
/// It is a REQUEST: only the server moves it from `requested` to `confirmed` or `declined`.
class ViewingRequest {
  final String id;
  final String listingId;
  final String listingTitle;
  final String? listingImage;
  final String? publicLocation;

  /// The caller represents the listing for its owner (rather than owning it).
  final bool representing;
  final String clientName;
  final String? clientAvatarUrl;

  /// Shared by the server only once the visit is confirmed.
  final String? clientPhone;

  /// requested | confirmed | declined | cancelled (and, rarely, in_progress | completed).
  final String status;
  final int startTime;
  final int endTime;
  final String? notes;
  final String? declineReason;
  final String? cancelReason;
  final int requestedAt;

  const ViewingRequest({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    this.listingImage,
    this.publicLocation,
    this.representing = false,
    this.clientName = 'Client',
    this.clientAvatarUrl,
    this.clientPhone,
    required this.status,
    required this.startTime,
    required this.endTime,
    this.notes,
    this.declineReason,
    this.cancelReason,
    this.requestedAt = 0,
  });

  factory ViewingRequest.fromMap(Map<String, dynamic> m) => ViewingRequest(
        id: _str(m['id'], _str(m['_id'])),
        listingId: _str(m['listingId']),
        listingTitle: _str(m['listingTitle'], 'Property'),
        listingImage: _optStr(m['listingImage']),
        publicLocation: _optStr(m['publicLocation']),
        representing: _bool(m['representing']),
        clientName: _str(m['clientName'], 'Client'),
        clientAvatarUrl: _optStr(m['clientAvatarUrl']),
        clientPhone: _optStr(m['clientPhone']),
        status: _str(m['status']),
        startTime: _int(m['startTime']),
        endTime: _int(m['endTime']),
        notes: _optStr(m['notes']),
        declineReason: _optStr(m['declineReason']),
        cancelReason: _optStr(m['cancelReason']),
        requestedAt: _int(m['requestedAt']),
      );

  bool get isRequested => status == 'requested';
  bool get isConfirmed => status == 'confirmed' || status == 'in_progress' || status == 'completed';

  /// The requested time is over: the server refuses to accept it, so only Decline is offered.
  bool isExpired(DateTime now) => endTime <= now.millisecondsSinceEpoch;

  ViewingTab get tab => switch (status) {
        'requested' => ViewingTab.pending,
        'declined' => ViewingTab.declined,
        'cancelled' => ViewingTab.cancelled,
        _ => ViewingTab.confirmed,
      };

  String get statusLabel => switch (status) {
        'requested' => 'Pending',
        'confirmed' => 'Confirmed',
        'in_progress' => 'In progress',
        'completed' => 'Completed',
        'declined' => 'Declined',
        'cancelled' => 'Cancelled',
        _ => status,
      };
}

/// The server already limits the list to property site visits on the caller's listings.
List<ViewingRequest> parseViewingRequests(dynamic rows) => mapList(rows).map(ViewingRequest.fromMap).toList();

// ═══════════════════════════════════════════════════════════════════════
//                             NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════

enum NotificationTab { all, messages, system, admin }

extension NotificationTabX on NotificationTab {
  String get label => switch (this) {
        NotificationTab.all => 'All',
        NotificationTab.messages => 'Messages',
        NotificationTab.system => 'System',
        NotificationTab.admin => 'Admin',
      };
}

/// `notifications:getUserNotifications` row.
class AgentNotification {
  final String id;

  /// single_user (sent to this account by the system) | all_users (broadcast by an administrator).
  final String targetType;
  final String title;
  final String body;
  final bool read;
  final int createdAt;
  final String? deepLinkScreen;
  final String? deepLinkId;

  const AgentNotification({
    required this.id,
    required this.targetType,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.deepLinkScreen,
    this.deepLinkId,
  });

  factory AgentNotification.fromMap(Map<String, dynamic> m) => AgentNotification(
        id: _str(m['id']),
        targetType: _str(m['targetType'], 'single_user'),
        title: _str(m['title']),
        body: _str(m['body']),
        read: _bool(m['read']),
        createdAt: _int(m['createdAt']),
        deepLinkScreen: _optStr(m['deepLinkScreen']),
        deepLinkId: _optStr(m['deepLinkId']),
      );

  /// Broadcasts can only be created by an administrator (notifications:createNotificationRecord).
  bool get isAdminAnnouncement => targetType == 'all_users';

  AgentNotification copyWith({bool? read}) => AgentNotification(
        id: id,
        targetType: targetType,
        title: title,
        body: body,
        read: read ?? this.read,
        createdAt: createdAt,
        deepLinkScreen: deepLinkScreen,
        deepLinkId: deepLinkId,
      );
}

/// Where a notification leads, from the server's deep link or clearly named event. Unknown → none.
enum NotificationDestination { none, conversation, viewings, bookings, listings, deals, earnings, subscription, followers }

NotificationDestination destinationFor(AgentNotification n) {
  switch (n.deepLinkScreen) {
    case 'messages':
      return NotificationDestination.conversation;
    case 'followers':
      return NotificationDestination.followers;
    case 'viewings':
      return NotificationDestination.viewings;
    case 'bookings':
      return NotificationDestination.bookings;
    case 'listings':
      return NotificationDestination.listings;
  }
  final t = '${n.title} ${n.body}'.toLowerCase();
  if (t.contains('listing agent') || t.contains('agent accepted') || t.contains('agent declined') || t.contains('represent')) {
    return NotificationDestination.listings;
  }
  if (t.contains('subscription')) return NotificationDestination.subscription;
  if (t.contains('booking') || t.contains('viewing') || t.contains('site visit')) return NotificationDestination.viewings;
  if (t.contains('escrow') || t.contains('contract') || t.contains('dispute') || t.contains('deposit claim') || t.contains('damage claim')) {
    return NotificationDestination.deals;
  }
  if (t.contains('payout') || t.contains('wallet') || t.contains('withdraw') || t.contains('funds received') || t.contains('payment received')) {
    return NotificationDestination.earnings;
  }
  if (t.contains('follower')) return NotificationDestination.followers;
  return NotificationDestination.none;
}

NotificationTab categoryOf(AgentNotification n) {
  if (n.isAdminAnnouncement) return NotificationTab.admin;
  return destinationFor(n) == NotificationDestination.conversation ? NotificationTab.messages : NotificationTab.system;
}

/// Server notifications for a tab, newest first.
List<AgentNotification> notificationsFor(List<AgentNotification> all, NotificationTab tab) {
  final list = all.where((n) => tab == NotificationTab.all || categoryOf(n) == tab).toList();
  list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
}

// ═══════════════════════════════════════════════════════════════════════
//                     DEALS, EARNINGS & PAYOUTS
// ═══════════════════════════════════════════════════════════════════════

/// Real-estate escrow states in which money is held or work is in progress.
const Set<String> activeDealStates = {
  'FUNDS_LOCKED',
  'AGENT_DISPATCHED',
  'CHECKED_IN',
  'MILESTONE_VERIFIED',
  'UNDER_ARBITRATION',
};

/// A real-estate escrow contract on one of the agent's own listings
/// (`realEstateEscrow:getMyRealEstateEscrows`, rows where the caller is the beneficiary).
class DealContract {
  final String id;
  final String code;
  final String contractType;
  final String state;
  final String propertyTitle;
  final String? propertyImage;
  final double grossAmount;
  final double platformFeeAmount;
  final double agentCommissionAmount;
  final double netBeneficiaryExpected;
  final double releasedBeneficiaryAmount;
  final double? escrowHeldRemaining;
  final int createdAt;

  const DealContract({
    required this.id,
    required this.code,
    required this.contractType,
    required this.state,
    required this.propertyTitle,
    this.propertyImage,
    this.grossAmount = 0,
    this.platformFeeAmount = 0,
    this.agentCommissionAmount = 0,
    this.netBeneficiaryExpected = 0,
    this.releasedBeneficiaryAmount = 0,
    this.escrowHeldRemaining,
    this.createdAt = 0,
  });

  factory DealContract.fromMap(Map<String, dynamic> m) => DealContract(
        id: _str(m['_id']),
        code: _str(m['contractCode']),
        contractType: _str(m['contractType']),
        state: _str(m['currentState']),
        propertyTitle: _str(m['propertyTitle'], 'Property'),
        propertyImage: _optStr(m['propertyImage']),
        grossAmount: _double(m['grossAmount']),
        platformFeeAmount: _double(m['platformFeeAmount']),
        agentCommissionAmount: _double(m['agentCommissionAmount']),
        netBeneficiaryExpected: _double(m['netBeneficiaryExpected']),
        releasedBeneficiaryAmount: _double(m['releasedBeneficiaryAmount']),
        escrowHeldRemaining: _optDouble(m['escrowHeldRemaining']),
        createdAt: _int(m['createdAt']),
      );

  bool get isActive => activeDealStates.contains(state);
  bool get isCompleted => state == 'FULLY_SETTLED';

  String get stateLabel => switch (state) {
        'CREATED' => 'Awaiting payment',
        'FUNDS_LOCKED' => 'Funds in escrow',
        'AGENT_DISPATCHED' => 'Agent dispatched',
        'CHECKED_IN' => 'Checked in',
        'MILESTONE_VERIFIED' => 'Milestone verified',
        'FULLY_SETTLED' => 'Completed',
        'UNDER_ARBITRATION' => 'In dispute',
        'REFUNDED' => 'Refunded',
        'CANCELLED' => 'Cancelled',
        _ => state,
      };
}

/// Contracts where the caller is the beneficiary (their own listings).
List<DealContract> parseOwnDeals(dynamic escrowsResponse) {
  final root = _map(escrowsResponse);
  return mapList(root['contracts'])
      .where((c) => c['isOwner'] == true)
      .map(DealContract.fromMap)
      .toList();
}

/// Viewing / inspection passes booked on listings the caller represents.
int countViewingRequests(dynamic escrowsResponse) {
  final root = _map(escrowsResponse);
  return mapList(root['inspectionPasses']).where((p) => p['isAgent'] == true).length;
}

/// `walletCore:getEarningsSummary` — the sum of real completed payouts credited to the caller.
class EarningsSummary {
  final double totalEarned;
  final String currency;
  final int count;
  final bool truncated;

  const EarningsSummary({required this.totalEarned, this.currency = 'SLE', this.count = 0, this.truncated = false});

  factory EarningsSummary.fromMap(Map<String, dynamic> m) => EarningsSummary(
        totalEarned: _double(m['totalEarned']),
        currency: _str(m['currency'], 'SLE'),
        count: _int(m['count']),
        truncated: _bool(m['truncated']),
      );
}

/// `wallet:getUserBalance`.
class WalletBalance {
  final double available;
  final double escrow;
  final double pending;
  final String currency;

  const WalletBalance({required this.available, this.escrow = 0, this.pending = 0, this.currency = 'SLE'});

  factory WalletBalance.fromMap(Map<String, dynamic> m) => WalletBalance(
        available: _double(m['availableBalance']),
        escrow: _double(m['escrowBalance']),
        pending: _double(m['pendingBalance']),
        currency: _str(m['currency'], 'SLE'),
      );
}

/// `withdrawals:getMyWithdrawals` row (the destination is already masked by the server).
class WithdrawalRecord {
  final String id;
  final double amount;
  final String currency;
  final String method;
  final String? provider;
  final String destination;
  final String status;
  final String? failureReason;
  final int createdAt;

  const WithdrawalRecord({
    required this.id,
    required this.amount,
    this.currency = 'SLE',
    this.method = '',
    this.provider,
    this.destination = '',
    required this.status,
    this.failureReason,
    required this.createdAt,
  });

  factory WithdrawalRecord.fromMap(Map<String, dynamic> m) => WithdrawalRecord(
        id: _str(m['id']),
        amount: _double(m['amount']),
        currency: _str(m['currency'], 'SLE'),
        method: _str(m['method']),
        provider: _optStr(m['provider']),
        destination: _str(m['destination']),
        status: _str(m['status']),
        failureReason: _optStr(m['failureReason']),
        createdAt: _int(m['createdAt']),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//                          PEOPLE (SOCIAL GRAPH)
// ═══════════════════════════════════════════════════════════════════════

/// `social:getFollowersList` / `social:getFollowingList` row.
class PersonSummary {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? verificationBadge;

  const PersonSummary({required this.id, required this.name, this.avatarUrl, this.verificationBadge});

  factory PersonSummary.fromMap(Map<String, dynamic> m) => PersonSummary(
        id: _str(m['_id']),
        name: _str(m['name'], 'Vektolux user'),
        avatarUrl: _optStr(m['avatarUrl']),
        verificationBadge: _optStr(m['verificationBadge']),
      );
}

/// Counts from `users:getUserProfile`.
class ProfileCounts {
  final int followers;
  final int following;
  final String? avatarUrl;
  final String? bio;
  const ProfileCounts({required this.followers, required this.following, this.avatarUrl, this.bio});

  factory ProfileCounts.fromMap(Map<String, dynamic> m) => ProfileCounts(
        followers: _int(m['followersCount']),
        following: _int(m['followingCount']),
        avatarUrl: _optStr(m['avatarUrl']),
        bio: _optStr(m['bio']),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//                               FORMATTING
// ═══════════════════════════════════════════════════════════════════════

final NumberFormat _whole = NumberFormat('#,##0', 'en_US');
final NumberFormat _cents = NumberFormat('#,##0.00', 'en_US');

/// "SLE 2,850,000" (whole amounts) or "SLE 1,250.50" (amounts with cents).
String formatMoney(num amount, {String currency = 'SLE', bool forceCents = false}) {
  final hasCents = amount != amount.roundToDouble();
  return '$currency ${(forceCents || hasCents) ? _cents.format(amount) : _whole.format(amount)}';
}

String formatCount(num n) => _whole.format(n);

String formatDate(int millis) => DateFormat('d MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(millis));

/// Message-list time: "10:24 AM" today, "Yesterday", "Mon" this week, else "12 Sep".
String formatListTime(int millis, {DateTime? now}) {
  if (millis <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return DateFormat('h:mm a').format(t);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(t);
  if (t.year == n.year) return DateFormat('d MMM').format(t);
  return DateFormat('d MMM yyyy').format(t);
}
