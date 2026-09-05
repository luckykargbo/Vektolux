// lib/features/mobility/presentation/widgets/in_app_chat_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — In-App Host & Dealer Chat Modal
// Direct messaging before booking or vehicle purchase with live text input,
// quick-reply chips, host profile details, and direct dial actions.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';

class InAppChatModal extends StatefulWidget {
  final String recipientName;
  final String recipientRole; // "Host / Fleet Manager" or "Verified Dealer"
  final String vehicleTitle;
  final String vehiclePrice;
  final String? vehicleImageUrl;
  final String? recipientPhone;

  const InAppChatModal({
    super.key,
    required this.recipientName,
    required this.recipientRole,
    required this.vehicleTitle,
    required this.vehiclePrice,
    this.vehicleImageUrl,
    this.recipientPhone,
  });

  static Future<void> show(
    BuildContext context, {
    required String recipientName,
    required String recipientRole,
    required String vehicleTitle,
    required String vehiclePrice,
    String? vehicleImageUrl,
    String? recipientPhone,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InAppChatModal(
        recipientName: recipientName,
        recipientRole: recipientRole,
        vehicleTitle: vehicleTitle,
        vehiclePrice: vehiclePrice,
        vehicleImageUrl: vehicleImageUrl,
        recipientPhone: recipientPhone,
      ),
    );
  }

  @override
  State<InAppChatModal> createState() => _InAppChatModalState();
}

class _InAppChatModalState extends State<InAppChatModal> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'host',
      'text': 'Hello! Thanks for your interest in the vehicle. How can I help you with your booking or inspection today?',
      'time': 'Just now',
    },
  ];

  final List<String> _quickInquiries = [
    'Is this vehicle available now?',
    'What is the security deposit?',
    'Can you deliver to my location?',
    'Is the mechanical report verified?',
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage([String? quickText]) {
    final text = quickText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'sender': 'user',
        'text': text,
        'time': 'Just now',
      });
    });

    if (quickText == null) {
      _messageController.clear();
    }

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    // Simulated host reply after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'sender': 'host',
          'text': 'Received your message! The vehicle is fully serviced, deed-verified, and ready in Freetown. You can proceed with booking or schedule a free inspection.',
          'time': 'Just now',
        });
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.emeraldSurface,
                  child: Text(
                    widget.recipientName.isNotEmpty ? widget.recipientName[0] : 'V',
                    style: const TextStyle(
                      color: AppColors.emeraldDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.recipientName,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const VerifiedBadge(size: VerifiedBadgeSize.small),
                        ],
                      ),
                      Text(
                        widget.recipientRole,
                        style: const TextStyle(color: AppColors.gray400, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_outlined, color: AppColors.emerald),
                  tooltip: 'Call Host',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Calling ${widget.recipientPhone ?? "+232 76 000000"}...'),
                        backgroundColor: AppColors.emerald,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // ── Vehicle Context Card ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.gray50,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.gray200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.directions_car, color: AppColors.obsidian, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.vehicleTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.vehiclePrice,
                        style: const TextStyle(
                          color: AppColors.emeraldDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Direct Inquiry',
                    style: TextStyle(
                      color: AppColors.emeraldDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Messages Stream ───────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.emerald : AppColors.gray100,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isUser ? const Radius.circular(2) : null,
                        bottomLeft: !isUser ? const Radius.circular(2) : null,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['text'] as String,
                          style: TextStyle(
                            color: isUser ? AppColors.white : AppColors.obsidian,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              msg['time'] as String,
                              style: TextStyle(
                                color: isUser
                                    ? AppColors.white.withValues(alpha: 0.7)
                                    : AppColors.gray500,
                                fontSize: 10,
                              ),
                            ),
                            if (isUser) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.done_all, size: 12, color: AppColors.white),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Quick Inquiries Chips ─────────────────────────────────
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: _quickInquiries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ActionChip(
                  label: Text(_quickInquiries[index]),
                  labelStyle: const TextStyle(fontSize: 11, color: AppColors.obsidian),
                  backgroundColor: AppColors.gray50,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onPressed: () => _sendMessage(_quickInquiries[index]),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // ── Text Input Field ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type your question or offer...',
                        hintStyle: TextStyle(fontSize: 13, color: AppColors.gray400),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.emerald,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: AppColors.white, size: 18),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
