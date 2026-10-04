// Rules of the Real Estate Agent workspace that decide what is shown (never what is allowed —
// the server authorises every action). All inputs are shaped like real Convex responses.

import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/features/agent/domain/agent_models.dart';
import 'package:vektolux/features/agent/presentation/bloc/agent_workspace_cubit.dart';

Map<String, dynamic> _status({
  String role = 'real_estate_agent',
  bool approved = true,
  bool subscribed = true,
  bool canPost = true,
  bool verified = true,
  bool grace = false,
  int? graceEnds,
  int? graceEnded,
  bool carDealer = false,
  List<Map<String, dynamic>> applications = const [],
}) =>
    {
      'role': role,
      'roleApproved': approved,
      'verifiedAgent': verified,
      'verifiedHotel': false,
      'agentExpiresAt': subscribed ? DateTime(2030).millisecondsSinceEpoch : null,
      'hotelExpiresAt': null,
      'hasActiveSubscription': subscribed,
      'isInGracePeriod': grace,
      'gracePeriodEndsAt': graceEnds,
      'legacyGraceEndedAt': graceEnded,
      'subscriptionPolicyConfigured': false,
      'canPostProperty': canPost,
      'canPostVehicle': carDealer,
      'isCarDealer': carDealer,
      'professionalTitle': carDealer ? 'Real Estate Agent & Car Dealer' : 'Real Estate Agent',
      'canManageHotel': false,
      'applications': applications,
    };

Map<String, dynamic> _ownListing({
  String id = 'l1',
  String category = 'sale',
  bool published = true,
  String availability = 'available',
  num price = 2850000,
  num? hourlyRate,
  String? lifecycle,
  String? reason,
}) =>
    {
      '_id': id,
      '_creationTime': 1700000000000,
      'ownerId': 'agent_1',
      'title': 'Modern 3 Bedroom House',
      'description': 'A bright family home',
      'category': category,
      'price': price,
      if (hourlyRate != null) 'hourlyRate': hourlyRate,
      'currency': 'SLE',
      // private fields the owner query returns — must never surface
      'address': '17 Hidden Close',
      'latitude': 8.4012,
      'longitude': -13.2123,
      'privateContactPhone': '+23277555999',
      'city': 'Aberdeen',
      'district': 'Western Area Urban',
      'country': 'Sierra Leone',
      'bedrooms': 3,
      'bathrooms': 2,
      'areaSqM': 167,
      'imageUrls': ['https://cdn.example/1.jpg', 'storage_id_not_a_url'],
      'availabilityStatus': availability,
      'isFeatured': false,
      'isPublished': published,
      'viewCount': 48,
      'saveCount': 5,
      'inquiryCount': 3,
      'viewingRequestCount': 2,
      if (lifecycle != null) 'lifecycleStatus': lifecycle,
      if (reason != null) 'moderationReason': reason,
      'updatedAt': 1700000000000,
    };

void main() {
  group('who gets the agent workspace (server status → view)', () {
    test('an approved Real Estate Agent gets the workspace', () {
      expect(ProfessionalStatus.fromMap(_status()).access, AgentAccess.approved);
    });

    test('a registered but unapproved agent sees the approval state, not the workspace', () {
      final s = ProfessionalStatus.fromMap(_status(approved: false, canPost: false, verified: false, subscribed: false));
      expect(s.access, AgentAccess.awaitingApproval);
    });

    test('a client whose agent application is under review sees the approval state', () {
      final s = ProfessionalStatus.fromMap(_status(role: 'client', approved: false, applications: [
        {'id': 'a1', 'targetRole': 'agent', 'status': 'pending', 'reviewNotes': null},
      ]));
      expect(s.access, AgentAccess.awaitingApproval);
    });

    test('a suspended or rejected applicant (client again) keeps the standard app', () {
      for (final status in ['suspended', 'rejected']) {
        final s = ProfessionalStatus.fromMap(_status(role: 'client', approved: false, applications: [
          {'id': 'a1', 'targetRole': 'agent', 'status': status, 'reviewNotes': 'Documents expired'},
        ]));
        expect(s.access, AgentAccess.none, reason: status);
      }
    });

    test('owners, dealers, hotel owners, admins and plain clients keep their own interfaces', () {
      for (final role in ['real_estate_owner', 'vehicle_dealer', 'hotel_owner', 'admin', 'client']) {
        expect(ProfessionalStatus.fromMap(_status(role: role)).access, AgentAccess.none, reason: role);
      }
    });

    test('an application for another role does not make a client a pending agent', () {
      final s = ProfessionalStatus.fromMap(_status(role: 'client', approved: false, applications: [
        {'id': 'a1', 'targetRole': 'property_owner', 'status': 'pending'},
      ]));
      expect(s.access, AgentAccess.none);
    });

    test('a malformed response never grants the workspace', () {
      expect(ProfessionalStatus.fromMap(const {}).access, AgentAccess.none);
      expect(ProfessionalStatus.fromMap(const {'role': 'real_estate_agent', 'roleApproved': 'yes'}).access,
          AgentAccess.awaitingApproval);
    });
  });

  group('professional identity (Real Estate Agent ± Car Dealer)', () {
    test('an agent is only a Real Estate Agent: no Auto tools', () {
      final s = ProfessionalStatus.fromMap(_status());
      expect(s.professionalTitle, 'Real Estate Agent');
      expect(s.isCarDealer, isFalse);
      expect(s.showAutoTools, isFalse);
    });

    test('a separately approved Car Dealer adds the Auto tools to the same account (server flags only)', () {
      final s = ProfessionalStatus.fromMap(_status(carDealer: true));
      expect(s.access, AgentAccess.approved);
      expect(s.professionalTitle, 'Real Estate Agent & Car Dealer');
      expect(s.showAutoTools, isTrue);
    });

    test('the app never promotes: a flag without the server posting permission shows no Auto tools', () {
      final s = ProfessionalStatus.fromMap({..._status(), 'isCarDealer': true, 'canPostVehicle': false});
      expect(s.showAutoTools, isFalse);
    });

    test('an older server without the fields leaves the plain agent workspace', () {
      final raw = _status()..remove('isCarDealer')..remove('canPostVehicle')..remove('professionalTitle');
      final s = ProfessionalStatus.fromMap(raw);
      expect(s.professionalTitle, 'Real Estate Agent');
      expect(s.showAutoTools, isFalse);
    });
  });

  group('posting permission and subscription label (server flags only)', () {
    test('posting is open only when the server says so', () {
      expect(ProfessionalStatus.fromMap(_status()).postingBlockedReason, isNull);
      expect(ProfessionalStatus.fromMap(_status(subscribed: false, canPost: false)).postingBlockedReason,
          contains('subscription is not active'));
      expect(ProfessionalStatus.fromMap(_status(approved: false, canPost: false)).postingBlockedReason,
          contains('awaiting approval'));
      final ended = DateTime.utc(2026, 1, 15).millisecondsSinceEpoch;
      expect(ProfessionalStatus.fromMap(_status(subscribed: false, canPost: false, graceEnded: ended)).postingBlockedReason,
          contains('grace period ended'));
    });

    test('a subscription label appears only for an active subscription', () {
      final now = DateTime(2026, 10, 3);
      final active = SubscriptionInfo.fromMap({
        'planName': 'Agent Pro',
        'status': 'active',
        'expiryDate': DateTime(2026, 11, 1).millisecondsSinceEpoch,
      });
      final expired = SubscriptionInfo.fromMap({
        'planName': 'Agent Pro',
        'status': 'active',
        'expiryDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
      });
      expect(subscriptionLabel(ProfessionalStatus.fromMap(_status()), active, now: now), 'Agent Pro');
      expect(subscriptionLabel(ProfessionalStatus.fromMap(_status()), expired, now: now), 'Active subscription');
      expect(subscriptionLabel(ProfessionalStatus.fromMap(_status(subscribed: false, canPost: false)), active, now: now), isNull);
      expect(
        subscriptionLabel(
            ProfessionalStatus.fromMap(_status(subscribed: false, grace: true, graceEnds: DateTime(2026, 10, 17).millisecondsSinceEpoch)),
            null,
            now: now),
        startsWith('Grace period until'),
      );
    });
  });

  group('listings', () {
    test('only public, generalised details are kept from the owner query', () {
      final l = AgentListing.fromOwn(_ownListing());
      expect(l.publicLocation, 'Aberdeen, Western Area Urban');
      expect(l.imageUrls, ['https://cdn.example/1.jpg'], reason: 'non-URL storage ids are not shown as images');
      final everything = [l.title, l.description, l.publicLocation, l.priceLabel, ...l.imageUrls].join(' ');
      expect(everything, isNot(contains('Hidden Close')));
      expect(everything, isNot(contains('555999')));
      expect(everything, isNot(contains('8.4012')));
    });

    test('location falls back to the district or the country, never an address', () {
      expect(const AgentListing(id: 'x', title: 't', category: 'sale', price: 1, town: 'Bo').publicLocation, 'Bo, Sierra Leone');
      expect(const AgentListing(id: 'x', title: 't', category: 'sale', price: 1, town: 'Bo', district: 'bo').publicLocation,
          'Bo, Sierra Leone');
      expect(const AgentListing(id: 'x', title: 't', category: 'sale', price: 1).publicLocation, 'Sierra Leone');
    });

    test('price labels follow the real category', () {
      expect(AgentListing.fromOwn(_ownListing()).priceLabel, 'SLE 2,850,000');
      expect(AgentListing.fromOwn(_ownListing(category: 'long_term_rent', price: 1200000)).priceLabel, 'SLE 1,200,000 / year');
      expect(AgentListing.fromOwn(_ownListing(category: 'hourly_guesthouse', price: 500, hourlyRate: 75)).priceLabel, 'SLE 75 / hr');
      expect(AgentListing.fromOwn(_ownListing(price: 0)).priceLabel, 'Price on request');
    });

    test('the status is the server\'s lifecycle; raw fields are only a fallback', () {
      for (final (server, expected, label) in const [
        ('active', ListingStatus.active, 'Active'),
        ('pending_review', ListingStatus.pendingReview, 'Pending review'),
        ('rejected', ListingStatus.rejected, 'Rejected'),
        ('removed', ListingStatus.removed, 'Removed'),
        ('draft', ListingStatus.draft, 'Draft'),
        ('unpublished', ListingStatus.unpublished, 'Unpublished'),
        ('off_market', ListingStatus.offMarket, 'Off-market'),
        ('archived', ListingStatus.archived, 'Archived'),
      ]) {
        final l = AgentListing.fromOwn(_ownListing(lifecycle: server));
        expect(l.status, expected, reason: server);
        expect(l.status.label, label);
      }
      // an old response without lifecycleStatus
      expect(AgentListing.fromOwn(_ownListing()).status, ListingStatus.active);
      expect(AgentListing.fromOwn(_ownListing(published: false)).status, ListingStatus.unpublished);
      expect(AgentListing.fromOwn(_ownListing(availability: 'booked')).status, ListingStatus.offMarket);
    });

    test('a rejection / removal reason and the statistics are the server\'s numbers', () {
      final l = AgentListing.fromOwn(_ownListing(lifecycle: 'rejected', reason: 'Photos do not show the property.'));
      expect(l.moderationReason, 'Photos do not show the property.');
      expect([l.viewCount, l.saveCount, l.inquiryCount, l.viewingRequestCount], [48, 5, 3, 2]);
      // a listing from the public record has no statistics (nothing is invented)
      final rep = AgentListing.fromPublic({'_id': 'p1', 'title': 'x', 'category': 'sale', 'price': 1}, representationId: 'a1');
      expect([rep.viewCount, rep.saveCount, rep.inquiryCount, rep.viewingRequestCount], [null, null, null, null]);
    });

    test('what the owner may do depends on the state (the server re-checks every action)', () {
      AgentListing st(String v) => AgentListing.fromOwn(_ownListing(lifecycle: v));
      expect(st('draft').canSubmitForReview, isTrue);
      expect(st('unpublished').canSubmitForReview, isTrue);
      expect(st('pending_review').canWithdraw, isTrue);
      expect(st('pending_review').canSubmitForReview, isFalse);
      expect(st('rejected').canResubmit, isTrue);
      expect(st('active').canUnpublish, isTrue);
      expect(st('active').canArchive, isTrue);
      expect(st('archived').canRestore, isTrue);
      expect(st('archived').canEdit, isFalse);
      final removed = st('removed');
      expect([removed.canEdit, removed.canArchive, removed.canSubmitForReview, removed.canResubmit], [false, false, false, false]);
      final represented = AgentListing.fromPublic({'_id': 'p1', 'title': 'x', 'category': 'sale', 'price': 1}, representationId: 'a1');
      expect([represented.canEdit, represented.canSubmitForReview, represented.canArchive], [false, false, false]);
    });

    test('filters: All plus only the statuses that apply to some (not all) of the listings', () {
      final list = [
        AgentListing.fromOwn(_ownListing(id: 'a', lifecycle: 'active')),
        AgentListing.fromOwn(_ownListing(id: 'b', category: 'long_term_rent', lifecycle: 'pending_review')),
        AgentListing.fromOwn(_ownListing(id: 'c', category: 'hourly_guesthouse', lifecycle: 'rejected')),
        AgentListing.fromOwn(_ownListing(id: 'd', lifecycle: 'draft')),
      ];
      expect(countMatching(list, ListingFilter.all), 4);
      expect(countMatching(list, ListingFilter.active), 1);
      expect(countMatching(list, ListingFilter.pendingReview), 1);
      expect(countMatching(list, ListingFilter.rejected), 1);
      expect(countMatching(list, ListingFilter.unpublished), 1, reason: 'drafts and unpublished listings');
      expect(countMatching(list, ListingFilter.sale), 2);
      expect(countMatching(list, ListingFilter.rent), 2);
      expect(visibleFilters(list),
          [ListingFilter.all, ListingFilter.active, ListingFilter.pendingReview, ListingFilter.rejected, ListingFilter.unpublished, ListingFilter.sale, ListingFilter.rent]);
      // nothing archived / removed / off-market → those filters are not offered
      final onlyActive = [AgentListing.fromOwn(_ownListing(lifecycle: 'active'))];
      expect(visibleFilters(onlyActive), [ListingFilter.all], reason: 'every listing is active: no redundant chips');
      // the selected filter always stays visible
      expect(visibleFilters(onlyActive, selected: ListingFilter.archived), [ListingFilter.all, ListingFilter.archived]);
    });

    test('a represented listing is marked as such', () {
      final l = AgentListing.fromPublic(
        {'_id': 'p9', 'title': 'Owner villa', 'category': 'sale', 'price': 900000, 'publicLocation': 'Inside Lumley, Sierra Leone'},
        representationId: 'auth1',
      );
      expect(l.isRepresented, isTrue);
      expect(l.publicLocation, 'Inside Lumley, Sierra Leone');
    });
  });

  group('notifications (real server rows only)', () {
    AgentNotification n(String id, String title,
            {String target = 'single_user', String? screen, String? linkId, bool read = false, int at = 0}) =>
        AgentNotification(
            id: id, targetType: target, title: title, body: '', read: read, createdAt: at, deepLinkScreen: screen, deepLinkId: linkId);

    test('the server deep link decides first', () {
      expect(destinationFor(n('a', 'New inquiry from Aminata', screen: 'messages', linkId: 'req1')), NotificationDestination.conversation);
      expect(destinationFor(n('b', 'New follower', screen: 'followers')), NotificationDestination.followers);
    });

    test('otherwise only clearly named events get a destination', () {
      expect(destinationFor(n('x', 'Listing agent invitation')), NotificationDestination.listings);
      expect(destinationFor(n('x', 'Subscription expiring soon')), NotificationDestination.subscription);
      expect(destinationFor(n('x', 'Booking paid')), NotificationDestination.viewings);
      expect(destinationFor(n('x', 'Escrow funded')), NotificationDestination.deals);
      expect(destinationFor(n('x', 'Payout completed to your wallet')), NotificationDestination.earnings);
      expect(destinationFor(n('x', 'Application approved')), NotificationDestination.none);
    });

    test('the deep link decides the screen: viewings, bookings, listings (moderation), conversations', () {
      expect(destinationFor(n('a', 'New viewing request', screen: 'viewings', linkId: 'b1')), NotificationDestination.viewings);
      expect(destinationFor(n('b', 'Your viewing request has been accepted.', screen: 'bookings', linkId: 'b1')), NotificationDestination.bookings);
      expect(destinationFor(n('c', 'Listing approved', screen: 'listings', linkId: 'l1')), NotificationDestination.listings);
    });

    test('tabs: Messages = conversations, Admin = broadcasts, System = everything else; newest first', () {
      final all = [
        n('1', 'New inquiry from Aminata', screen: 'messages', at: 5),
        n('2', 'Planned maintenance', target: 'all_users', read: true, at: 1),
        n('3', 'Booking confirmed', at: 4),
        n('4', 'Escrow funded', at: 3),
        n('5', 'Application approved', at: 2),
        n('6', 'Listing not approved', screen: 'listings', at: 6),
      ];
      expect(notificationsFor(all, NotificationTab.all).map((x) => x.id), ['6', '1', '3', '4', '5', '2']);
      expect(notificationsFor(all, NotificationTab.messages).map((x) => x.id), ['1']);
      expect(notificationsFor(all, NotificationTab.admin).map((x) => x.id), ['2']);
      expect(notificationsFor(all, NotificationTab.system).map((x) => x.id), ['6', '3', '4', '5']);
      expect(NotificationTab.values.map((t) => t.label), ['All', 'Messages', 'System', 'Admin']);
    });

    test('a server row keeps its deep link; marking read changes nothing else', () {
      final row = AgentNotification.fromMap(const {
        'id': 'n1', 'targetType': 'single_user', 'title': 'New inquiry from Aminata', 'body': 'About "Villa": hi',
        'read': false, 'createdAt': 3000, 'deepLinkScreen': 'messages', 'deepLinkId': 'req_9',
      });
      final read = row.copyWith(read: true);
      expect([read.read, read.deepLinkScreen, read.deepLinkId, read.title], [true, 'messages', 'req_9', 'New inquiry from Aminata']);
    });
  });

  group('viewing requests (a request the agent accepts or declines)', () {
    final now = DateTime(2026, 10, 3, 12);
    Map<String, dynamic> row(String id, String status, DateTime start, {String? reason, String? phone}) => {
          'id': id, 'listingId': 'l1', 'listingTitle': 'Villa', 'listingImage': 'https://cdn.example/v.jpg',
          'publicLocation': 'Inside Lumley, Sierra Leone', 'representing': false, 'clientName': 'Aminata', 'status': status,
          'startTime': start.millisecondsSinceEpoch, 'endTime': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          'notes': 'Can we meet at the gate?', if (reason != null) 'declineReason': reason, if (phone != null) 'clientPhone': phone,
          'requestedAt': 1,
        };

    test('each server status lands in its tab; requested is Pending (never Confirmed)', () {
      final list = parseViewingRequests([
        row('b1', 'requested', DateTime(2026, 10, 4, 10)),
        row('b2', 'confirmed', DateTime(2026, 10, 5, 10), phone: '+23276123456'),
        row('b3', 'declined', DateTime(2026, 10, 6, 10), reason: 'House being repainted'),
        row('b4', 'cancelled', DateTime(2026, 10, 7, 10)),
        row('b5', 'completed', DateTime(2026, 9, 1, 10)),
      ]);
      expect(list.map((v) => v.tab), [ViewingTab.pending, ViewingTab.confirmed, ViewingTab.declined, ViewingTab.cancelled, ViewingTab.confirmed]);
      expect(list.map((v) => v.statusLabel), ['Pending', 'Confirmed', 'Declined', 'Cancelled', 'Completed']);
      expect(list[0].isRequested, isTrue);
      expect(list[0].isConfirmed, isFalse);
      expect(list[2].declineReason, 'House being repainted');
      expect(list[1].clientPhone, '+23276123456');
      expect(list[0].clientPhone, isNull, reason: 'the server shares the phone only once the visit is confirmed');
      expect(ViewingTab.values.map((t) => t.label), ['Pending', 'Confirmed', 'Declined', 'Cancelled']);
    });

    test('a request whose time has passed can only be declined', () {
      final v = parseViewingRequests([row('b1', 'requested', DateTime(2026, 10, 1, 10))]).single;
      expect(v.isExpired(now), isTrue);
      expect(parseViewingRequests([row('b2', 'requested', DateTime(2026, 10, 4, 10))]).single.isExpired(now), isFalse);
    });

    test('the cubit state counts pending requests and picks the next confirmed visit from the server list', () {
      final sooner = DateTime.now().add(const Duration(days: 1));
      final later = DateTime.now().add(const Duration(days: 3));
      final viewings = parseViewingRequests([
        row('p', 'requested', sooner),
        row('c2', 'confirmed', later),
        row('c1', 'confirmed', sooner),
        row('d', 'declined', sooner),
      ]);
      final state = AgentWorkspaceState(status: ProfessionalStatus.fromMap(_status()), viewings: Loadable<List<ViewingRequest>>(data: viewings));
      expect(state.pendingViewings, 1);
      expect(state.nextViewing(DateTime.now())?.id, 'c1');
      expect(AgentWorkspaceState(status: ProfessionalStatus.fromMap(_status())).pendingViewings, 0, reason: 'nothing loaded → no invented number');
    });
  });

  group('deals and money', () {
    test('only contracts on the agent\'s own listings count, active by escrow state', () {
      final deals = parseOwnDeals({
        'contracts': [
          {'_id': 'c1', 'contractCode': 'VX-1', 'currentState': 'FUNDS_LOCKED', 'isOwner': true, 'propertyTitle': 'A'},
          {'_id': 'c2', 'contractCode': 'VX-2', 'currentState': 'FULLY_SETTLED', 'isOwner': true, 'propertyTitle': 'B'},
          {'_id': 'c3', 'contractCode': 'VX-3', 'currentState': 'FUNDS_LOCKED', 'isOwner': false, 'propertyTitle': 'C'},
        ],
        'inspectionPasses': [
          {'isAgent': true},
          {'isAgent': false},
        ],
      });
      expect(deals.map((d) => d.code), ['VX-1', 'VX-2']);
      expect(deals.where((d) => d.isActive).length, 1);
      expect(countViewingRequests({'inspectionPasses': [{'isAgent': true}, {'isAgent': false}]}), 1);
    });

    test('money and time formatting', () {
      expect(formatMoney(2850000), 'SLE 2,850,000');
      expect(formatMoney(1250.5), 'SLE 1,250.50');
      expect(formatMoney(12, forceCents: true), 'SLE 12.00');
      final now = DateTime(2026, 10, 3, 15, 0);
      expect(formatListTime(DateTime(2026, 10, 3, 10, 24).millisecondsSinceEpoch, now: now), '10:24 AM');
      expect(formatListTime(DateTime(2026, 10, 2, 9).millisecondsSinceEpoch, now: now), 'Yesterday');
      expect(formatListTime(DateTime(2026, 9, 28).millisecondsSinceEpoch, now: now), 'Mon');
      expect(formatListTime(DateTime(2026, 8, 12).millisecondsSinceEpoch, now: now), '12 Aug');
    });
  });
}
