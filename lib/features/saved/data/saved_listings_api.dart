// lib/features/saved/data/saved_listings_api.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Saved listings (the heart) over the existing Convex backend.
//   savedListings:toggleSavedListing / getMySavedListingIds / getMySavedListings
// The server record belongs to the signed-in account (the session decides who); the app never
// names the user. Saves therefore survive logging out, reinstalling and other devices.
// ═══════════════════════════════════════════════════════════════════════

import '../../../core/network/convex_client_wrapper.dart';
import '../domain/saved_listing.dart';

class SavedListingsException implements Exception {
  final String message;
  const SavedListingsException(this.message);

  @override
  String toString() => message;
}

/// The server's message, or a clear one when the connected server does not have saves yet.
String savedServerMessage(String? raw) {
  final m = raw?.trim() ?? '';
  if (m.isEmpty) return 'Something went wrong. Please try again.';
  if (m.contains('Could not find public function')) {
    return 'Saved properties become available after the next Vektolux server update.';
  }
  // Convex wraps server errors: "[CONVEX M(...)] Uncaught Error: <message>" — show only <message>.
  final match = RegExp(r'Uncaught Error: ([^\n]+)').firstMatch(m);
  return (match?.group(1) ?? m).trim();
}

class SavedListingsApi {
  final ConvexClientWrapper client;
  final String? sessionToken;

  const SavedListingsApi({required this.client, this.sessionToken});

  Map<String, dynamic> _args([Map<String, dynamic> args = const {}]) => {
        ...args,
        if (sessionToken != null && sessionToken!.isNotEmpty) 'sessionToken': sessionToken,
      };

  /// Ids of everything the account has saved (for the hearts).
  Future<Set<String>> savedIds() async {
    final res = await client.query('savedListings:getMySavedListingIds', args: _args());
    if (!res.success) throw SavedListingsException(savedServerMessage(res.errorMessage));
    final v = res.value;
    return {
      for (final r in (v is List ? v : const []))
        if (r is Map && r['listingId'] != null) r['listingId'].toString(),
    };
  }

  /// Saves or un-saves; returns the state the SERVER now holds.
  Future<bool> toggle({required String listingType, required String listingId}) async {
    final res = await client.mutation(
      'savedListings:toggleSavedListing',
      args: _args({'listingType': listingType, 'listingId': listingId}),
    );
    if (!res.success) throw SavedListingsException(savedServerMessage(res.errorMessage));
    final v = res.value;
    return v is Map && v['saved'] == true;
  }

  Future<List<SavedListing>> savedListings() async {
    final res = await client.query('savedListings:getMySavedListings', args: _args());
    if (!res.success) throw SavedListingsException(savedServerMessage(res.errorMessage));
    final v = res.value;
    return (v is List ? v : const [])
        .whereType<Map>()
        .map((m) => SavedListing.fromMap(Map<String, dynamic>.from(m)))
        .where((s) => s.listingId.isNotEmpty)
        .toList();
  }
}
