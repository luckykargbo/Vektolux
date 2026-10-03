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

  group('notifications feed', () {
    final notifications = [
      AgentNotification.fromMap(const {
        'id': 'n1', 'targetType': 'single_user', 'title': 'Subscription active', 'body': 'Your plan is active.', 'read': false, 'createdAt': 3000,
      }),
      AgentNotification.fromMap(const {
        'id': 'n2', 'targetType': 'all_users', 'title': 'Planned maintenance', 'body': 'Saturday night.', 'read': true, 'createdAt': 1000,
      }),
    ];
    final inquiries = [
      Inquiry.fromMap(const {
        'id': 'q1', 'buyerName': 'Aminata Kamara', 'listingId': 'l1', 'listingType': 'property',
        'message': 'Is this still available?', 'status': 'pending', 'createdAt': 2000,
      }),
    ];

    test('categories: inquiries are messages, broadcasts are admin, the rest is system', () {
      expect(buildFeed(notifications, inquiries, NotificationTab.all).map((i) => i.title).toList(),
          ['Subscription active', 'New message from Aminata Kamara', 'Planned maintenance']);
      expect(buildFeed(notifications, inquiries, NotificationTab.admin).single.title, 'Planned maintenance');
      expect(buildFeed(notifications, inquiries, NotificationTab.system).single.title, 'Subscription active');
      expect(buildFeed(notifications, inquiries, NotificationTab.messages).single.unread, isTrue);
    });

    test('destinations are only set when the server text clearly names them', () {
      AgentNotification n(String title) =>
          AgentNotification(id: 'x', targetType: 'single_user', title: title, body: '', read: false, createdAt: 0);
      expect(destinationFor(n('Listing agent invitation')), NotificationDestination.listings);
      expect(destinationFor(n('Subscription expiring soon')), NotificationDestination.subscription);
      expect(destinationFor(n('Booking paid')), NotificationDestination.bookings);
      expect(destinationFor(n('Escrow funded')), NotificationDestination.deals);
      expect(destinationFor(n('Application approved')), NotificationDestination.none);
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
