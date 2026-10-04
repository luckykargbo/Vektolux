// lib/features/messaging/domain/messaging_models.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Buyer ↔ seller conversations (convex/messaging.ts). Parsed from the server only:
// names, avatars and the listing's public summary — never phone numbers, emails or addresses.
// ═══════════════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';

String _s(dynamic v, [String f = '']) => v == null ? f : v.toString();
String? _os(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

int _i(dynamic v) => v is num ? v.toInt() : 0;
Map<String, dynamic> _m(dynamic v) => v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

final NumberFormat _money = NumberFormat('#,##0', 'en_US');

class ChatPerson {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isVerified;

  const ChatPerson({required this.id, required this.name, this.avatarUrl, this.isVerified = false});

  factory ChatPerson.fromMap(Map<String, dynamic> m) => ChatPerson(
        id: _s(m['id']),
        name: _s(m['name'], 'Vektolux user'),
        avatarUrl: _os(m['avatarUrl']),
        isVerified: m['isVerified'] == true,
      );
}

/// Public summary of the listing a conversation is about.
class ChatListing {
  final String id;
  final String type;
  final String title;
  final String category;
  final num price;
  final num? hourlyRate;
  final String currency;
  final String? imageUrl;
  final String location;

  const ChatListing({
    required this.id,
    required this.type,
    required this.title,
    this.category = '',
    this.price = 0,
    this.hourlyRate,
    this.currency = 'SLE',
    this.imageUrl,
    this.location = '',
  });

  factory ChatListing.fromMap(Map<String, dynamic> m) => ChatListing(
        id: _s(m['id']),
        type: _s(m['type'], 'property'),
        title: _s(m['title'], 'Listing'),
        category: _s(m['category']),
        price: m['price'] is num ? m['price'] as num : 0,
        hourlyRate: m['hourlyRate'] is num ? m['hourlyRate'] as num : null,
        currency: _s(m['currency'], 'SLE'),
        imageUrl: _os(m['imageUrl']),
        location: _s(m['location']),
      );

  String get priceLabel {
    final rate = hourlyRate;
    if (category == 'hourly_guesthouse' && rate != null && rate > 0) return '$currency ${_money.format(rate)} / hr';
    if (price <= 0) return 'Price on request';
    if (category == 'long_term_rent') return '$currency ${_money.format(price)} / year';
    if (category == 'car_rental') return '$currency ${_money.format(price)} / day';
    return '$currency ${_money.format(price)}';
  }
}

class Conversation {
  final String id;

  /// buyer | seller — the caller's side of this conversation.
  final String myRole;

  /// pending | accepted | declined (declined = closed).
  final String status;
  final ChatPerson counterpart;
  final String listingId;
  final String listingType;
  final ChatListing? listing;
  final String lastMessage;
  final int lastMessageAt;
  final bool lastMessageFromMe;
  final int unread;
  final int createdAt;

  const Conversation({
    required this.id,
    required this.myRole,
    required this.status,
    required this.counterpart,
    required this.listingId,
    required this.listingType,
    this.listing,
    required this.lastMessage,
    required this.lastMessageAt,
    this.lastMessageFromMe = false,
    this.unread = 0,
    this.createdAt = 0,
  });

  factory Conversation.fromMap(Map<String, dynamic> m) => Conversation(
        id: _s(m['id']),
        myRole: _s(m['myRole'], 'buyer'),
        status: _s(m['status'], 'pending'),
        counterpart: ChatPerson.fromMap(_m(m['counterpart'])),
        listingId: _s(m['listingId']),
        listingType: _s(m['listingType'], 'property'),
        listing: m['listing'] is Map ? ChatListing.fromMap(_m(m['listing'])) : null,
        lastMessage: _s(m['lastMessage']),
        lastMessageAt: _i(m['lastMessageAt']),
        lastMessageFromMe: m['lastMessageFromMe'] == true,
        unread: _i(m['unread']),
        createdAt: _i(m['createdAt']),
      );

  bool get isClosed => status == 'declined';
  bool get isSeller => myRole == 'seller';

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return counterpart.name.toLowerCase().contains(q) ||
        lastMessage.toLowerCase().contains(q) ||
        (listing?.title.toLowerCase().contains(q) ?? false);
  }
}

class ChatMessage {
  final String id;
  final bool fromMe;
  final String body;
  final int createdAt;
  final int? readAt;

  const ChatMessage({required this.id, required this.fromMe, required this.body, required this.createdAt, this.readAt});

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: _s(m['id']),
        fromMe: m['fromMe'] == true,
        body: _s(m['body']),
        createdAt: _i(m['createdAt']),
        readAt: m['readAt'] is num ? (m['readAt'] as num).toInt() : null,
      );
}

class ChatThread {
  final Conversation conversation;
  final bool canSend;
  final bool truncated;
  final List<ChatMessage> messages;

  const ChatThread({required this.conversation, required this.canSend, this.truncated = false, required this.messages});

  factory ChatThread.fromMap(Map<String, dynamic> m) => ChatThread(
        conversation: Conversation.fromMap(_m(m['conversation'])),
        canSend: m['canSend'] == true,
        truncated: m['truncated'] == true,
        messages: (m['messages'] is List ? m['messages'] as List : const [])
            .whereType<Map>()
            .map((x) => ChatMessage.fromMap(_m(x)))
            .toList(),
      );
}

/// "10:24 AM" today, "Yesterday", "Mon" this week, else "12 Sep".
String chatListTime(int millis, {DateTime? now}) {
  if (millis <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return DateFormat('h:mm a').format(t);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(t);
  return DateFormat(t.year == n.year ? 'd MMM' : 'd MMM yyyy').format(t);
}
