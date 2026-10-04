// lib/features/messaging/presentation/conversation_tile.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — One conversation in an inbox: person, the property it is about, last message,
// time and unread count.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/components/verified_badge.dart';
import '../../../core/widgets/vektolux_avatar.dart';
import '../domain/messaging_models.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationTile({super.key, required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
    return Material(
      color: Colors.white,
      child: InkWell(
        key: Key('conversation-${c.id}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.gray100))),
          child: Row(
            children: [
              VektoluxAvatar(avatarUrl: c.counterpart.avatarUrl, name: c.counterpart.name, radius: 24, borderWidth: 0),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  c.counterpart.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                ),
                              ),
                              if (c.counterpart.isVerified) ...[
                                const SizedBox(width: 4),
                                const VerifiedBadge(customTooltip: 'Identity verified'),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chatListTime(c.lastMessageAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: unread ? AppColors.emeraldDark : AppColors.gray400,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (c.listing != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.home_work_outlined, size: 12.5, color: AppColors.emeraldDark),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              c.isSeller ? 'Interested in: ${c.listing!.title}' : c.listing!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.emeraldDark, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c.lastMessageFromMe ? 'You: ' : ''}${c.lastMessage}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: unread ? AppColors.obsidian : AppColors.gray500),
                          ),
                        ),
                        if (c.isClosed)
                          const _Chip(label: 'Closed')
                        else if (unread)
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.emeraldDark, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              c.unread > 99 ? '99+' : '${c.unread}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.gray600)),
      );
}
