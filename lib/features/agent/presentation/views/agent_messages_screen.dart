// lib/features/agent/presentation/views/agent_messages_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent inbox (Messages tab).
// Real conversations with clients about the agent's listings (messaging:getMyConversations,
// seller side). Each row shows the client, the property they are interested in, the last
// message, the time and the unread count; a conversation opens the shared thread screen with a
// real composer. Nothing private (phone, email, address) is returned or shown.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../messaging/presentation/conversation_tile.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_navigation.dart';

class AgentMessagesScreen extends StatefulWidget {
  const AgentMessagesScreen({super.key});

  @override
  State<AgentMessagesScreen> createState() => _AgentMessagesScreenState();
}

class _AgentMessagesScreenState extends State<AgentMessagesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
            builder: (context, s) {
              final all = s.conversations.data;
              final visible = all?.where((c) => c.matches(_search.text)).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, AgentTokens.gutter, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Messages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                        ),
                        if (s.unreadMessages > 0)
                          AgentPill(
                            label: '${s.unreadMessages} unread',
                            background: AppColors.emeraldSurface,
                            foreground: AppColors.emeraldDark,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, AgentTokens.gutter, 6),
                    child: TextField(
                      key: const Key('agent-messages-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search conversations…',
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.gray400),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.gray50,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                        enabledBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.emerald,
                      onRefresh: cubit.loadConversations,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (visible == null && s.conversations.error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                              child: AgentErrorState(message: s.conversations.error!, onRetry: cubit.loadConversations),
                            )
                          else if (visible == null)
                            const AgentLoading()
                          else if ((all ?? const []).isEmpty)
                            const AgentEmptyState(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'No messages yet',
                              message: 'Client questions about your listings appear here.',
                            )
                          else if (visible.isEmpty)
                            const AgentEmptyState(icon: Icons.search_off_rounded, title: 'No matches', message: 'Try another name or property.')
                          else
                            for (final c in visible) ConversationTile(conversation: c, onTap: () => openConversation(context, c.id)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
