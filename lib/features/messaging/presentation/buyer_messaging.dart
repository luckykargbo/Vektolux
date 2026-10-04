// lib/features/messaging/presentation/buyer_messaging.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Conversations outside the agent workspace: the inbox, and "message the seller" from
// a listing (opens the existing open conversation about that listing, or sends the first message).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/messaging_api.dart';
import '../domain/messaging_models.dart';
import 'conversation_screen.dart';
import 'conversation_tile.dart';

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

/// Opens the buyer's conversation about a listing (or starts one with a first message).
Future<void> openListingConversation(
  BuildContext context, {
  required MessagingApi api,
  required String listingId,
  required String listingType,
  required String listingTitle,
}) async {
  List<Conversation> mine;
  try {
    mine = await api.conversations(role: 'buyer');
  } on MessagingException catch (e) {
    if (context.mounted) _snack(context, e.message);
    return;
  }
  if (!context.mounted) return;
  Conversation? existing;
  for (final c in mine) {
    if (c.listingId == listingId && !c.isClosed) existing = c;
  }
  if (existing != null) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(api: api, conversationId: existing!.id)));
    return;
  }
  final message = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _FirstMessageSheet(listingTitle: listingTitle),
  );
  if (message == null || !context.mounted) return;
  try {
    final id = await api.startInquiry(listingId: listingId, listingType: listingType, message: message);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(api: api, conversationId: id)));
  } on MessagingException catch (e) {
    if (context.mounted) _snack(context, e.message);
  }
}

class _FirstMessageSheet extends StatefulWidget {
  final String listingTitle;
  const _FirstMessageSheet({required this.listingTitle});

  @override
  State<_FirstMessageSheet> createState() => _FirstMessageSheetState();
}

class _FirstMessageSheetState extends State<_FirstMessageSheet> {
  static const _quick = [
    'Is this property still available?',
    'Can I schedule a viewing?',
    'Can you send more photos?',
    'Is the price negotiable?',
  ];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Message the seller', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            const SizedBox(height: 2),
            Text(widget.listingTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.emeraldDark)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 12, color: AppColors.obsidian)),
                    backgroundColor: AppColors.gray50,
                    side: const BorderSide(color: AppColors.border),
                    onPressed: () => setState(() => _text.text = q),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('first-message-input'),
              controller: _text,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Write your question…',
                filled: true,
                fillColor: AppColors.gray50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('first-message-send'),
                onPressed: _text.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_text.text.trim()),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emeraldDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.gray200,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The user's conversations: questions they sent about listings and, for owners, questions
/// clients sent about theirs.
class MessagesInboxScreen extends StatefulWidget {
  final MessagingApi api;

  /// 'buyer' or 'seller' to show one side only; null shows both.
  final String? role;
  const MessagesInboxScreen({super.key, required this.api, this.role});

  @override
  State<MessagesInboxScreen> createState() => _MessagesInboxScreenState();
}

class _MessagesInboxScreenState extends State<MessagesInboxScreen> {
  List<Conversation>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.conversations(role: widget.role);
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } on MessagingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: RefreshIndicator(
        color: AppColors.emerald,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (items == null && _error != null)
              _CenteredNote(icon: Icons.cloud_off_rounded, title: _error!, action: TextButton(onPressed: _load, child: const Text('Retry')))
            else if (items == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.emerald)))
            else if (items.isEmpty)
              const _CenteredNote(icon: Icons.chat_bubble_outline_rounded, title: 'No messages yet', subtitle: 'Message a seller from any property.')
            else
              for (final c in items)
                ConversationTile(
                  conversation: c,
                  onTap: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ConversationScreen(api: widget.api, conversationId: c.id)));
                    _load();
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _CenteredNote({required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.gray300),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.gray500)),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      );
}
