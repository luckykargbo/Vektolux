// Rules of the Real Estate Agent workspace that decide what is shown (never what is allowed —
// the server authorises every action). All inputs are shaped like real Convex responses.

import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/features/agent/domain/agent_models.dart';

Map<String, dynamic> _status({
  String role = 'real_estate_agent',
  bool approved = true,
  bool subscribed = true,
  bool canPost = true,
  bool verified = true,
  bool grace = false,
  int? graceEnds,
  int? graceEnded,
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
      'canPostVehicle': false,
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

    test('status comes from the server fields', () {
      expect(AgentListing.fromOwn(_ownListing()).liveStatus, ListingLiveStatus.live);
      expect(AgentListing.fromOwn(_ownListing(published: false)).liveStatus, ListingLiveStatus.unpublished);
      expect(AgentListing.fromOwn(_ownListing(availability: 'booked')).liveStatus, ListingLiveStatus.booked);
      expect(AgentListing.fromOwn(_ownListing(availability: 'maintenance')).liveStatus.label, 'Maintenance');
      expect(AgentListing.fromOwn(_ownListing(published: false)).liveStatus.label, 'Unpublished');
    });

    test('filters and their counts', () {
      final list = [
        AgentListing.fromOwn(_ownListing(id: 'a')),
        AgentListing.fromOwn(_ownListing(id: 'b', category: 'long_term_rent', published: false)),
        AgentListing.fromOwn(_ownListing(id: 'c', category: 'hourly_guesthouse')),
      ];
      expect(countMatching(list, ListingFilter.all), 3);
      expect(countMatching(list, ListingFilter.sale), 1);
      expect(countMatching(list, ListingFilter.rent), 2);
      expect(countMatching(list, ListingFilter.unpublished), 1);
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

    test('tabs: broadcasts are Admin; the rest by destination; anything else is Account; newest first', () {
      final all = [
        n('1', 'New inquiry from Aminata', screen: 'messages', at: 5),
        n('2', 'Planned maintenance', target: 'all_users', read: true, at: 1),
        n('3', 'Booking confirmed', at: 4),
        n('4', 'Escrow funded', at: 3),
        n('5', 'Application approved', at: 2),
        n('6', 'Listing agent invitation', at: 6),
      ];
      expect(notificationsFor(all, NotificationTab.all).map((x) => x.id), ['6', '1', '3', '4', '5', '2']);
      expect(notificationsFor(all, NotificationTab.messages).single.id, '1');
      expect(notificationsFor(all, NotificationTab.admin).single.id, '2');
      expect(notificationsFor(all, NotificationTab.viewings).single.id, '3');
      expect(notificationsFor(all, NotificationTab.deals).single.id, '4');
      expect(notificationsFor(all, NotificationTab.account).single.id, '5');
      expect(notificationsFor(all, NotificationTab.listings).single.id, '6');
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

  group('viewing requests (existing booking states)', () {
    int ms(DateTime d) => d.millisecondsSinceEpoch;
    final now = DateTime(2026, 10, 3, 12);
    Map<String, dynamic> booking(String id, String status, DateTime start,
            {String listingType = 'property', String type = 'property_inspection'}) =>
        {
          '_id': id, 'listingType': listingType, 'listingId': 'l1', 'listingTitle': 'Villa', 'bookingType': type,
          'status': status, 'startTime': ms(start), 'endTime': ms(start.add(const Duration(hours: 1))), 'buyerName': 'Aminata',
        };

    test('only property bookings, tabbed by the server status and the time', () {
      final list = parseViewingRequests([
        booking('b1', 'confirmed', DateTime(2026, 10, 4, 10)),
        booking('b2', 'completed', DateTime(2026, 9, 30, 10)),
        booking('b3', 'cancelled', DateTime(2026, 10, 5, 10)),
        booking('b4', 'confirmed', DateTime(2026, 10, 4, 10), listingType: 'vehicle'),
        booking('b5', 'confirmed', DateTime(2026, 9, 1, 10), type: 'short_stay'),
      ]);
      expect(list.map((v) => v.id), ['b1', 'b2', 'b3', 'b5']);
      expect(list.map((v) => v.tabAt(now)), [ViewingTab.upcoming, ViewingTab.past, ViewingTab.cancelled, ViewingTab.past]);
      expect([list[0].typeLabel, list[0].statusLabel], ['Site visit', 'Confirmed']);
      expect([list[3].typeLabel, list[1].statusLabel], ['Short stay', 'Completed']);
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
