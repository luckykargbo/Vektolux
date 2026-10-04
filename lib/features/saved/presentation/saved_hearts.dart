// lib/features/saved/presentation/saved_hearts.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — State behind the heart buttons. The SERVER is the source of truth: the saved ids are
// loaded from it, and a tap updates the heart at once but is confirmed (or rolled back with the
// server's message) when the server answers. Signed-out users are asked to log in.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/convex_client_wrapper.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/saved_listings_api.dart';

class SavedHearts extends ChangeNotifier {
  final SavedListingsApi? _api;
  SavedHearts(this._api);

  /// Built from the app's providers. Without a signed-in user (or without the providers, e.g. in
  /// an isolated widget test) the hearts simply ask the user to log in.
  factory SavedHearts.of(BuildContext context) {
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) return SavedHearts(null);
      return SavedHearts(SavedListingsApi(client: context.read<ConvexClientWrapper>(), sessionToken: user.sessionToken));
    } catch (_) {
      return SavedHearts(null);
    }
  }

  final Set<String> _ids = {};
  final Set<String> _inFlight = {};
  bool _disposed = false;

  bool get signedIn => _api != null;
  bool isSaved(String listingId) => _ids.contains(listingId);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Loads what the account has saved. A failure leaves the hearts empty (never invented).
  Future<void> load() async {
    final api = _api;
    if (api == null) return;
    try {
      final ids = await api.savedIds();
      _ids
        ..clear()
        ..addAll(ids);
      _changed();
    } catch (_) {
      // hearts stay unfilled; tapping one reports the real problem
    }
  }

  /// Toggles a heart. Returns a message to show when it did not work, else null.
  Future<String?> toggle(String listingId, {String type = 'property'}) async {
    final api = _api;
    if (api == null) return 'Log in to save properties.';
    if (listingId.isEmpty || _inFlight.contains(listingId)) return null;
    _inFlight.add(listingId);
    final was = _ids.contains(listingId);
    was ? _ids.remove(listingId) : _ids.add(listingId); // optimistic
    _changed();
    try {
      final saved = await api.toggle(listingType: type, listingId: listingId);
      saved ? _ids.add(listingId) : _ids.remove(listingId); // the server's answer wins
      return null;
    } on SavedListingsException catch (e) {
      was ? _ids.add(listingId) : _ids.remove(listingId); // roll back
      return e.message;
    } finally {
      _inFlight.remove(listingId);
      _changed();
    }
  }
}
