// lib/features/agent/presentation/views/agent_messages_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent inbox (Messages tab) and conversation view.
//
// Built on the messaging the backend actually has: buyers' in-app inquiries about a listing
// (contact_requests: adminPortal:getSellerContactRequests / respondToContactRequest). Each
// inquiry is one buyer message; the agent can accept or decline it (recorded by the server).
// There is no free-text reply API, so no reply box is offered and no message is ever "sent"
// locally — the screen says so. The buyer's phone number is never returned and never shown.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../data/agent_api.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_navigation.dart';
import 'agent_shell.dart';

/// Title of the listing an inquiry is about (from the agent's loaded portfolio).
AgentListing? listingForInquiry(AgentWorkspaceState s, Inquiry i) {
  for (final l in s.portfolio ?? const <AgentListing>[]) {
    if (l.id == i.listingId) return l;
  }
  return null;
}

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
              final all = s.inquiries.data;
              final visible = all
                  ?.where((i) => i.matchesSearch(_search.text, listingTitle: listingForInquiry(s, i)?.title))
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(AgentTokens.gutter, 12, AgentTokens.gutter, 0),
                    child: Text('Messages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(AgentTokens.gutter, 2, AgentTokens.gutter, 0),
                    child: Text('Inquiries from buyers about your listings',
                        style: TextStyle(fontSize: 12.5, color: AppColors.gray500)),
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
                      onRefresh: cubit.loadInquiries,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (visible == null && s.inquiries.error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                              child: AgentErrorState(message: s.inquiries.error!, onRetry: cubit.loadInquiries),
                            )
                          else if (visible == null)
                            const AgentLoading(label: 'Loading messages…')
                          else if ((all ?? const []).isEmpty)
                            const AgentEmptyState(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'No messages yet',
                              message: 'When a buyer sends an inquiry about one of your listings, it appears here.',
                            )
                          else if (visible.isEmpty)
                            const AgentEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No matches',
                              message: 'No conversation matches your search.',
                            )
                          else
                            for (final i in visible) _InquiryTile(inquiry: i, listing: listingForInquiry(s, i)),
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

class _InquiryTile extends StatelessWidget {
  final Inquiry inquiry;
  final AgentListing? listing;
  const _InquiryTile({required this.inquiry, required this.listing});

  @override
  Widget build(BuildContext context) {
    final unread = inquiry.isPending;
    return InkWell(
      key: Key('agent-inquiry-${inquiry.id}'),
      onTap: () => pushAgentPage(context, AgentConversationScreen(inquiryId: inquiry.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.gray100))),
        child: Row(
          children: [
            VektoluxAvatar(avatarUrl: inquiry.buyerAvatarUrl, name: inquiry.buyerName, radius: 24, borderWidth: 0),
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
                                inquiry.buyerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w700, color: AppColors.obsidian),
                              ),
                            ),
                            if (inquiry.buyerIsVerified) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(customTooltip: 'Identity verified buyer'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatListTime(inquiry.createdAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: unread ? AppColors.emeraldDark : AppColors.gray400,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          inquiry.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: unread ? AppColors.obsidian : AppColors.gray500),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.emeraldDark, shape: BoxShape.circle),
                          child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${listing != null ? 'Re: ${listing!.title}' : 'About one of your listings'} · ${inquiry.statusLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.gray400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One inquiry: the buyer's message, its property, and the actions the server supports.
class AgentConversationScreen extends StatefulWidget {
  final String inquiryId;
  const AgentConversationScreen({super.key, required this.inquiryId});

  @override
  State<AgentConversationScreen> createState() => _AgentConversationScreenState();
}

class _AgentConversationScreenState extends State<AgentConversationScreen> {
  bool _busy = false;

  Future<void> _respond(Inquiry inquiry, bool accept) async {
    final confirmed = await agentConfirm(
      context,
      title: accept ? 'Accept this inquiry?' : 'Decline this inquiry?',
      message: accept
          ? 'Accepting allows Vektolux to share your phone number with ${inquiry.buyerName} so they can contact you. '
              'This cannot be undone.'
          : 'The inquiry will be marked as declined. This cannot be undone.',
      confirmLabel: accept ? 'Accept' : 'Decline',
      destructive: !accept,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await context.read<AgentWorkspaceCubit>().respondToInquiry(inquiry, accept: accept);
      if (mounted) agentSnack(context, result.status == 'ACCEPTED' ? 'Inquiry accepted.' : 'Inquiry declined.');
    } on AgentApiException catch (e) {
      if (mounted) agentSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return agentTextScale(
      BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
        builder: (context, s) {
          Inquiry? inquiry;
          for (final i in s.inquiries.data ?? const <Inquiry>[]) {
            if (i.id == widget.inquiryId) inquiry = i;
          }
          if (inquiry == null) {
            return Scaffold(
              appBar: AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.obsidian, elevation: 0),
              body: const AgentEmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Conversation unavailable',
                message: 'This inquiry is no longer available.',
              ),
            );
          }
          final listing = listingForInquiry(s, inquiry);
          return _conversation(context, inquiry, listing);
        },
      ),
    );
  }

  Widget _conversation(BuildContext context, Inquiry inquiry, AgentListing? listing) {
    return Scaffold(
      backgroundColor: AgentTokens.page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            VektoluxAvatar(avatarUrl: inquiry.buyerAvatarUrl, name: inquiry.buyerName, radius: 18, borderWidth: 0),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inquiry.buyerName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  Text(inquiry.statusLabel, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (listing != null)
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => openListingDetail(context, listing),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter, vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: Row(
                    children: [
                      AgentThumb(url: listing.coverImage, size: 46),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(listing.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                            Text('${listing.priceLabel} · ${listing.publicLocation}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AgentTokens.gutter),
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(10)),
                    child: Text(formatDate(inquiry.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.gray500)),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    child: Container(
                      key: const Key('agent-conversation-message'),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                          bottomLeft: Radius.circular(4),
                        ),
                        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inquiry.message, style: const TextStyle(fontSize: 14, color: AppColors.obsidian, height: 1.35)),
                          const SizedBox(height: 4),
                          Text(formatListTime(inquiry.createdAt), style: const TextStyle(fontSize: 10.5, color: AppColors.gray400)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (inquiry.respondedAt != null) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      inquiry.status == 'accepted'
                          ? 'You accepted this inquiry on ${formatDate(inquiry.respondedAt!)}.'
                          : 'You declined this inquiry on ${formatDate(inquiry.respondedAt!)}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 10, AgentTokens.gutter, 10),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AgentInfoNote(
                    key: const Key('agent-conversation-no-reply'),
                    text: inquiry.isPending
                        ? 'In-app replies are not available yet. You can accept or decline this inquiry.'
                        : 'In-app replies are not available yet.',
                  ),
                  if (inquiry.isPending) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('agent-inquiry-decline'),
                            onPressed: _busy ? null : () => _respond(inquiry, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.gray700,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            key: const Key('agent-inquiry-accept'),
                            onPressed: _busy ? null : () => _respond(inquiry, true),
                            style: agentPrimaryButtonStyle(),
                            child: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
