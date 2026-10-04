// lib/features/agent/presentation/bloc/agent_workspace_cubit.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent workspace state.
//
// Holds the server data shared by the agent tabs (listings, client conversations, viewing
// requests, unread count, deals, earnings, profile) so the dashboard, the tabs and the
// navigation badges agree. Every value comes from a Convex response; after any action the data
// is re-read from the server instead of being assumed.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../messaging/data/messaging_api.dart';
import '../../../messaging/domain/messaging_models.dart';
import '../../data/agent_api.dart';
import '../../domain/agent_models.dart';

/// A server value with its loading / error state. `data` keeps the last good value while a
/// refresh runs or fails, so a temporary error never blanks or fakes what was already shown.
class Loadable<T> {
  final T? data;
  final bool isLoading;
  final String? error;

  const Loadable({this.data, this.isLoading = false, this.error});

  Loadable<T> loading() => Loadable<T>(data: data, isLoading: true);
  Loadable<T> success(T value) => Loadable<T>(data: value);
  Loadable<T> failure(String message) => Loadable<T>(data: data, error: message);

  bool get hasData => data != null;

  /// Nothing to show yet (first load running or not started).
  bool get isPending => data == null && error == null;
}

class AgentWorkspaceState {
  final ProfessionalStatus status;
  final SubscriptionInfo? subscription;
  final Loadable<List<AgentListing>> ownListings;

  /// Listings the agent represents for their owners (active authorisations).
  final Loadable<List<AgentListing>> representedListings;

  /// Pending owner invitations to represent a listing.
  final Loadable<List<AgentInvitation>> invitations;

  /// Conversations with clients about the agent's listings.
  final Loadable<List<Conversation>> conversations;
  final Loadable<List<ViewingRequest>> viewings;
  final Loadable<int> unreadNotifications;
  final Loadable<List<DealContract>> deals;
  final int viewingPasses;
  final Loadable<EarningsSummary> earnings;
  final Loadable<ProfileCounts> profile;

  const AgentWorkspaceState({
    required this.status,
    this.subscription,
    this.ownListings = const Loadable(),
    this.representedListings = const Loadable(),
    this.invitations = const Loadable(),
    this.conversations = const Loadable(),
    this.viewings = const Loadable(),
    this.unreadNotifications = const Loadable(),
    this.deals = const Loadable(),
    this.viewingPasses = 0,
    this.earnings = const Loadable(),
    this.profile = const Loadable(),
  });

  AgentWorkspaceState copyWith({
    ProfessionalStatus? status,
    SubscriptionInfo? subscription,
    bool clearSubscription = false,
    Loadable<List<AgentListing>>? ownListings,
    Loadable<List<AgentListing>>? representedListings,
    Loadable<List<AgentInvitation>>? invitations,
    Loadable<List<Conversation>>? conversations,
    Loadable<List<ViewingRequest>>? viewings,
    Loadable<int>? unreadNotifications,
    Loadable<List<DealContract>>? deals,
    int? viewingPasses,
    Loadable<EarningsSummary>? earnings,
    Loadable<ProfileCounts>? profile,
  }) =>
      AgentWorkspaceState(
        status: status ?? this.status,
        subscription: clearSubscription ? null : (subscription ?? this.subscription),
        ownListings: ownListings ?? this.ownListings,
        representedListings: representedListings ?? this.representedListings,
        invitations: invitations ?? this.invitations,
        conversations: conversations ?? this.conversations,
        viewings: viewings ?? this.viewings,
        unreadNotifications: unreadNotifications ?? this.unreadNotifications,
        deals: deals ?? this.deals,
        viewingPasses: viewingPasses ?? this.viewingPasses,
        earnings: earnings ?? this.earnings,
        profile: profile ?? this.profile,
      );

  /// Own listings plus represented ones (whatever has loaded), newest first. Null until the
  /// agent's own listings have loaded.
  List<AgentListing>? get portfolio {
    final own = ownListings.data;
    if (own == null) return null;
    return newestFirst([...own, ...?representedListings.data]);
  }

  int? get activeDeals => deals.data?.where((d) => d.isActive).length;

  /// Unread client messages (server counters).
  int get unreadMessages => conversations.data?.fold<int>(0, (sum, c) => sum + c.unread) ?? 0;
  int get unreadCount => unreadNotifications.data ?? 0;

  /// Real inquiries per listing id (conversations opened about it).
  Map<String, int> get inquiriesByListing {
    final out = <String, int>{};
    for (final c in conversations.data ?? const <Conversation>[]) {
      out[c.listingId] = (out[c.listingId] ?? 0) + 1;
    }
    return out;
  }

  /// Site-visit requests waiting for the agent's answer (server status "requested").
  int get pendingViewings => viewings.data?.where((v) => v.isRequested).length ?? 0;

  /// The soonest confirmed visit that has not ended yet.
  ViewingRequest? nextViewing(DateTime now) {
    ViewingRequest? next;
    for (final v in viewings.data ?? const <ViewingRequest>[]) {
      if (!v.isConfirmed || v.isExpired(now)) continue;
      if (next == null || v.startTime < next.startTime) next = v;
    }
    return next;
  }
}

class AgentWorkspaceCubit extends Cubit<AgentWorkspaceState> {
  final AgentApi api;

  AgentWorkspaceCubit({required this.api, required ProfessionalStatus status}) : super(AgentWorkspaceState(status: status));

  MessagingApi get messaging => api.messaging;

  void _emit(AgentWorkspaceState s) {
    if (!isClosed) emit(s);
  }

  String _message(Object e) => e is AgentApiException
      ? e.message
      : e is MessagingException
          ? e.message
          : 'Something went wrong. Please try again.';

  /// Loads everything the tabs show. Each part fails independently.
  Future<void> loadAll() => Future.wait([
        refreshStatus(),
        loadListings(),
        loadRepresentations(),
        loadConversations(),
        loadViewings(),
        loadUnreadCount(),
        loadDeals(),
        loadEarnings(),
        loadProfile(),
      ]);

  Future<void> refreshStatus() async {
    try {
      final status = await api.professionalStatus();
      if (status != null) _emit(state.copyWith(status: status));
    } catch (_) {
      // keep the status the shell resolved; screens show their own errors
    }
    try {
      final sub = await api.activeSubscription();
      _emit(sub == null ? state.copyWith(clearSubscription: true) : state.copyWith(subscription: sub));
    } catch (_) {
      // the label then falls back to the server's hasActiveSubscription flag
    }
  }

  Future<void> loadListings() async {
    _emit(state.copyWith(ownListings: state.ownListings.loading()));
    try {
      final list = await api.myListings();
      _emit(state.copyWith(ownListings: state.ownListings.success(list)));
    } catch (e) {
      _emit(state.copyWith(ownListings: state.ownListings.failure(_message(e))));
    }
  }

  Future<void> loadRepresentations() async {
    _emit(state.copyWith(
      representedListings: state.representedListings.loading(),
      invitations: state.invitations.loading(),
    ));
    try {
      final auths = (await api.myAuthorizations()).where((a) => a.isProperty && (a.isActive || a.isPending)).toList();
      final views = await Future.wait(auths.map((a) async {
        try {
          final m = await api.publicProperty(a.listingId);
          return m == null ? null : AgentListing.fromPublic(m, representationId: a.id);
        } catch (_) {
          return null; // that one listing could not load; the others still show
        }
      }));
      final represented = <AgentListing>[];
      final invitations = <AgentInvitation>[];
      for (var i = 0; i < auths.length; i++) {
        if (auths[i].isActive) {
          if (views[i] != null) represented.add(views[i]!);
        } else {
          invitations.add(AgentInvitation(auths[i], views[i]));
        }
      }
      _emit(state.copyWith(
        representedListings: state.representedListings.success(represented),
        invitations: state.invitations.success(invitations),
      ));
    } catch (e) {
      _emit(state.copyWith(
        representedListings: state.representedListings.failure(_message(e)),
        invitations: state.invitations.failure(_message(e)),
      ));
    }
  }

  Future<void> loadConversations() async {
    _emit(state.copyWith(conversations: state.conversations.loading()));
    try {
      final list = await messaging.conversations(role: 'seller');
      _emit(state.copyWith(conversations: state.conversations.success(list)));
    } catch (e) {
      _emit(state.copyWith(conversations: state.conversations.failure(_message(e))));
    }
  }

  Future<void> loadViewings() async {
    _emit(state.copyWith(viewings: state.viewings.loading()));
    try {
      final list = await api.viewingRequests();
      // Pending first (soonest first), then the rest by time.
      list.sort((a, b) {
        if (a.isRequested != b.isRequested) return a.isRequested ? -1 : 1;
        return a.startTime.compareTo(b.startTime);
      });
      _emit(state.copyWith(viewings: state.viewings.success(list)));
    } catch (e) {
      _emit(state.copyWith(viewings: state.viewings.failure(_message(e))));
    }
  }

  Future<void> loadUnreadCount() async {
    _emit(state.copyWith(unreadNotifications: state.unreadNotifications.loading()));
    try {
      final n = await api.unreadNotificationCount();
      _emit(state.copyWith(unreadNotifications: state.unreadNotifications.success(n)));
    } catch (e) {
      _emit(state.copyWith(unreadNotifications: state.unreadNotifications.failure(_message(e))));
    }
  }

  Future<void> loadDeals() async {
    _emit(state.copyWith(deals: state.deals.loading()));
    try {
      final raw = await api.realEstateEscrows();
      _emit(state.copyWith(deals: state.deals.success(parseOwnDeals(raw)), viewingPasses: countViewingRequests(raw)));
    } catch (e) {
      _emit(state.copyWith(deals: state.deals.failure(_message(e))));
    }
  }

  Future<void> loadEarnings() async {
    _emit(state.copyWith(earnings: state.earnings.loading()));
    try {
      final summary = await api.earningsSummary();
      _emit(state.copyWith(earnings: state.earnings.success(summary)));
    } catch (e) {
      _emit(state.copyWith(earnings: state.earnings.failure(_message(e))));
    }
  }

  Future<void> loadProfile() async {
    _emit(state.copyWith(profile: state.profile.loading()));
    try {
      final counts = await api.profileCounts();
      _emit(counts == null
          ? state.copyWith(profile: state.profile.failure('Profile not found.'))
          : state.copyWith(profile: state.profile.success(counts)));
    } catch (e) {
      _emit(state.copyWith(profile: state.profile.failure(_message(e))));
    }
  }

  // ─── Actions (the server decides; the data is re-read afterwards) ─────

  /// Returns null on success, else the server's message.
  Future<String?> _run(Future<void> Function() action, List<Future<void> Function()> reload) async {
    try {
      await action();
      await Future.wait(reload.map((r) => r()));
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  /// Submit for review (`publish: true`) or unpublish / withdraw (`false`); the server decides the
  /// resulting state and the list is re-read.
  Future<String?> setPublished(AgentListing listing, bool publish) =>
      _run(() => api.setPublished(listing.id, publish), [loadListings]);

  Future<String?> archiveListing(AgentListing listing) => _run(() => api.archiveListing(listing.id), [loadListings]);

  Future<String?> restoreListing(AgentListing listing) => _run(() => api.restoreListing(listing.id), [loadListings]);

  Future<String?> deleteListing(AgentListing listing) => _run(() => api.deleteListing(listing.id), [loadListings]);

  Future<String?> updateListingDetails(
    AgentListing listing, {
    String? title,
    String? description,
    double? price,
    int? bedrooms,
    int? bathrooms,
  }) =>
      _run(
        () => api.updateListingDetails(listing.id,
            title: title, description: description, price: price, bedrooms: bedrooms, bathrooms: bathrooms),
        [loadListings],
      );

  Future<String?> respondToInvitation(AgentInvitation invitation, {required bool accept}) =>
      _run(() => api.respondToInvitation(invitation.authorization.id, accept: accept), [loadRepresentations]);

  Future<String?> stopRepresenting(AgentListing listing, String reason) {
    final id = listing.representationId;
    if (id == null) return Future.value('This is not a represented listing.');
    return _run(() => api.stopRepresenting(id, reason), [loadRepresentations]);
  }

  Future<String?> respondToViewing(ViewingRequest viewing, {required bool accept, String? reason}) =>
      _run(() => api.respondToViewing(viewing.id, accept: accept, reason: reason), [loadViewings, loadListings]);

  Future<String?> cancelViewing(ViewingRequest viewing, String reason) =>
      _run(() => api.cancelViewing(viewing.id, reason), [loadViewings]);

  Future<String?> updateBio(String bio) => _run(() => api.updateBio(bio), [loadProfile]);

  /// Called by the notifications screen after it marks items read on the server.
  void setUnreadCount(int count) =>
      _emit(state.copyWith(unreadNotifications: state.unreadNotifications.success(count < 0 ? 0 : count)));
}
