// lib/features/messaging/presentation/conversation_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — One conversation: the property it is about, the message history and a composer.
// Messages are sent to and re-read from the server (nothing is shown as sent before the server
// accepts it). While open, the thread refreshes every few seconds; incoming messages are marked
// read on the server. "Seen" comes from the server's read receipts.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/vektolux_avatar.dart';
import '../data/messaging_api.dart';
import '../domain/messaging_models.dart';

class ConversationScreen extends StatefulWidget {
  final MessagingApi api;
  final String conversationId;

  /// Opens the listing the conversation is about (optional).
  final void Function(BuildContext context, ChatListing listing)? onOpenListing;

  /// How often the open thread is refreshed (zero disables refreshing, e.g. in tests).
  final Duration refreshEvery;

  const ConversationScreen({
    super.key,
    required this.api,
    required this.conversationId,
    this.onOpenListing,
    this.refreshEvery = const Duration(seconds: 6),
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  ChatThread? _thread;
  String? _error;
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.refreshEvery > Duration.zero) {
      _timer = Timer.periodic(widget.refreshEvery, (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final t = await widget.api.thread(widget.conversationId);
      if (!mounted) return;
      final grew = (t.messages.length) > (_thread?.messages.length ?? 0);
      setState(() {
        _thread = t;
        _error = null;
      });
      if (t.conversation.unread > 0) {
        widget.api.markRead(widget.conversationId).catchError((_) {});
      }
      if (grew) _scrollToEnd();
    } on MessagingException catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = e.message);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.send(widget.conversationId, body);
      _input.clear();
      await _load();
    } on MessagingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _closeInquiry() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Close this conversation?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text('The client will be told the inquiry was declined.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorDark),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.respond(widget.conversationId, accept: false);
      await _load();
    } on MessagingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _thread;
    final c = t?.conversation;
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 0,
        title: c == null
            ? const Text('Conversation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))
            : Row(
                children: [
                  VektoluxAvatar(avatarUrl: c.counterpart.avatarUrl, name: c.counterpart.name, radius: 18, borderWidth: 0),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.counterpart.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                        Text(c.isSeller ? 'Client' : 'Seller',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.gray500, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (c != null && c.isSeller && c.status == 'pending')
            PopupMenuButton<String>(
              key: const Key('chat-menu'),
              color: Colors.white,
              onSelected: (_) => _closeInquiry(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'close', child: Text('Close conversation'))],
            ),
        ],
      ),
      body: t == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: AppColors.gray400, size: 40),
                          const SizedBox(height: 10),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray600)),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(color: AppColors.emerald),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c!.listing != null) _ListingBar(listing: c.listing!, onTap: widget.onOpenListing),
                Expanded(child: _messages(t)),
                if (t.canSend) _composer() else const _ClosedBar(),
              ],
            ),
    );
  }

  Widget _messages(ChatThread t) {
    final items = <Widget>[];
    DateTime? day;
    for (final m in t.messages) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.createdAt);
      final thisDay = DateTime(d.year, d.month, d.day);
      if (day != thisDay) {
        day = thisDay;
        items.add(_DayChip(day: thisDay));
      }
      items.add(_Bubble(message: m));
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: items,
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat-input'),
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Write a message…',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.gray50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.emeraldDark)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: _input.text.trim().isEmpty || _sending ? AppColors.gray200 : AppColors.emeraldDark,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('chat-send'),
                  customBorder: const CircleBorder(),
                  onTap: _input.text.trim().isEmpty || _sending ? null : _send,
                  child: Center(
                    child: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingBar extends StatelessWidget {
  final ChatListing listing;
  final void Function(BuildContext context, ChatListing listing)? onTap;
  const _ListingBar({required this.listing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = listing.imageUrl;
    final placeholder = Container(
      width: 44,
      height: 44,
      color: AppColors.gray100,
      alignment: Alignment.center,
      child: const Icon(Icons.home_work_outlined, color: AppColors.gray400, size: 20),
    );
    return Material(
      color: Colors.white,
      child: InkWell(
        key: const Key('chat-listing'),
        onTap: onTap == null ? null : () => onTap!(context, listing),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: img == null
                    ? placeholder
                    : Image.network(img, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    Text(
                      [listing.priceLabel, if (listing.location.isNotEmpty) listing.location].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.gray500),
                    ),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final DateTime day;
  const _DayChip({required this.day});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0 ? 'Today' : (diff == 1 ? 'Yesterday' : DateFormat('EEE d MMM').format(day));
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.gray500, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.fromMe;
    final time = DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(message.createdAt));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          key: Key('chat-msg-${message.id}'),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.emeraldDark : Colors.white,
            border: mine ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(message.body, style: TextStyle(fontSize: 14, height: 1.35, color: mine ? Colors.white : AppColors.obsidian)),
              const SizedBox(height: 3),
              Text(
                mine && message.readAt != null ? '$time · Seen' : time,
                style: TextStyle(fontSize: 10.5, color: mine ? Colors.white70 : AppColors.gray400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosedBar extends StatelessWidget {
  const _ClosedBar();

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          key: const Key('chat-closed'),
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.gray500),
              SizedBox(width: 6),
              Text('This conversation is closed', style: TextStyle(color: AppColors.gray600, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
