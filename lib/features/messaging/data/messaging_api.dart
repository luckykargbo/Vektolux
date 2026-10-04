// lib/features/messaging/data/messaging_api.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Conversations API (existing Convex functions only).
//   messaging:getMyConversations / getThread / sendMessage / markThreadRead
//   adminPortal:submitContactRequest (a buyer's first message about a listing)
//   adminPortal:respondToContactRequest (the seller accepts / declines = closes)
// Identity is the session; the server checks that the caller takes part in the thread.
// ═══════════════════════════════════════════════════════════════════════

import '../../../core/network/convex_client_wrapper.dart';
import '../domain/messaging_models.dart';

class MessagingException implements Exception {
  final String message;
  const MessagingException(this.message);

  @override
  String toString() => message;
}

/// The server's message, or a clear one when the connected server does not have messaging yet.
String friendlyServerMessage(String? raw, {String fallback = 'Something went wrong. Please try again.'}) {
  final m = raw?.trim() ?? '';
  if (m.isEmpty) return fallback;
  if (m.contains('Could not find public function')) {
    return 'Messaging becomes available after the next Vektolux server update.';
  }
  return m;
}

class MessagingApi {
  final ConvexClientWrapper client;
  final String userId;
  final String? sessionToken;

  const MessagingApi({required this.client, required this.userId, this.sessionToken});

  Map<String, dynamic> _session([Map<String, dynamic> args = const {}]) => {
        ...args,
        if (sessionToken != null && sessionToken!.isNotEmpty) 'sessionToken': sessionToken,
      };

  Future<dynamic> _call(Future<ConvexResult> Function() call) async {
    final res = await call();
    if (!res.success) throw MessagingException(friendlyServerMessage(res.errorMessage));
    return res.value;
  }

  /// [role]: 'seller' (clients asking about my listings), 'buyer' (my questions), or null (both).
  Future<List<Conversation>> conversations({String? role}) async {
    final v = await _call(() => client.query('messaging:getMyConversations', args: _session({if (role != null) 'role': role})));
    return (v is List ? v : const []).whereType<Map>().map((m) => Conversation.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<ChatThread> thread(String conversationId) async {
    final v = await _call(() => client.query('messaging:getThread', args: _session({'requestId': conversationId})));
    if (v is! Map) throw const MessagingException('Conversation not found.');
    return ChatThread.fromMap(Map<String, dynamic>.from(v));
  }

  Future<void> send(String conversationId, String body) =>
      _call(() => client.mutation('messaging:sendMessage', args: _session({'requestId': conversationId, 'body': body})));

  Future<void> markRead(String conversationId) =>
      _call(() => client.mutation('messaging:markThreadRead', args: _session({'requestId': conversationId})));

  /// A buyer's first message about a listing; returns the new conversation id.
  Future<String> startInquiry({required String listingId, required String listingType, required String message}) async {
    final v = await _call(() => client.mutation('adminPortal:submitContactRequest',
        args: _session({'buyerId': userId, 'listingId': listingId, 'listingType': listingType, 'message': message})));
    final id = v is Map ? v['requestId']?.toString() : null;
    if (id == null || id.isEmpty) throw const MessagingException('The message could not be sent.');
    return id;
  }

  /// The seller accepts or declines (closes) an inquiry.
  Future<void> respond(String conversationId, {required bool accept}) => _call(() => client.mutation(
        'adminPortal:respondToContactRequest',
        args: _session({'sellerId': userId, 'requestId': conversationId, 'action': accept ? 'accepted' : 'declined'}),
      ));
}
