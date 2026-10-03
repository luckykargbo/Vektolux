// lib/features/agent/presentation/views/agent_notifications_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent notifications (Notifications tab).
//
// Tabs: All · Messages · System · Admin.
//   Messages — buyer inquiries (real contact requests; unread = not yet answered)
//   System   — notifications the server sent to this account (bookings, escrow, payouts,
//              subscription, role decisions, listing-agent invitations …)
//   Admin    — broadcast announcements (only an administrator can create these)
// Read state, time and the unread count are the server's. Nothing is generated locally.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_earnings_screen.dart';
import 'agent_messages_screen.dart';
import 'agent_navigation.dart';
import 'agent_shell.dart';

class AgentNotificationsScreen extends StatefulWidget {
  const AgentNotificationsScreen({super.key});

  @override
  State<AgentNotificationsScreen> createState() => _AgentNotificationsScreenState();
}

class _AgentNotificationsScreenState extends State<AgentNotificationsScreen> {
  NotificationTab _tab = NotificationTab.all;
  List<AgentNotification>? _items;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<AgentWorkspaceCubit>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await cubit.api.notifications();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      cubit.loadUnreadCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => Future.wait([_load(), context.read<AgentWorkspaceCubit>().loadInquiries()]);

  Future<void> _markAllRead() async {
    final cubit = context.read<AgentWorkspaceCubit>();
    try {
      await cubit.api.markAllNotificationsRead();
      await _load();
    } catch (e) {
      if (mounted) agentSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _open(FeedItem item) async {
    final cubit = context.read<AgentWorkspaceCubit>();
    final inquiry = item.inquiry;
    if (inquiry != null) {
      pushAgentPage(context, AgentConversationScreen(inquiryId: inquiry.id));
      return;
    }
    final n = item.notification!;
    if (!n.read) {
      try {
        await cubit.api.markNotificationRead(n.id);
        if (!mounted) return;
        setState(() => _items = [for (final x in _items ?? const <AgentNotification>[]) x.id == n.id ? x.copyWith(read: true) : x]);
        cubit.loadUnreadCount();
      } catch (e) {
        if (mounted) agentSnack(context, e.toString(), error: true);
        return;
      }
    }
    if (!mounted) return;
    switch (destinationFor(n)) {
      case NotificationDestination.listings:
        AgentShellScope.of(context).openTab(AgentTab.listings);
      case NotificationDestination.deals:
        openDeals(context);
      case NotificationDestination.earnings:
        pushAgentPage(context, const AgentEarningsScreen());
      case NotificationDestination.subscription:
        openSubscription(context);
      case NotificationDestination.bookings:
        openBookings(context);
      case NotificationDestination.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
            builder: (context, s) {
              final items = _items;
              final inquiries = s.inquiries.data ?? const <Inquiry>[];
              final feed = items == null ? null : buildFeed(items, inquiries, _tab);
              final hasUnread = items?.any((n) => !n.read) ?? false;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, 8, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Notifications',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                        ),
                        if (hasUnread)
                          TextButton(
                            key: const Key('agent-mark-all-read'),
                            onPressed: _markAllRead,
                            style: TextButton.styleFrom(foregroundColor: AppColors.emeraldDark),
                            child: const Text('Mark all read', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                    child: Row(
                      children: [
                        for (final t in NotificationTab.values) ...[
                          if (t != NotificationTab.values.first) const SizedBox(width: 8),
                          _tabChip(t),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.emerald,
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (feed == null && _error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                              child: AgentErrorState(message: _error!, onRetry: _load),
                            )
                          else if (feed == null || (_loading && feed.isEmpty))
                            const AgentLoading(label: 'Loading notifications…')
                          else if (feed.isEmpty)
                            _empty()
                          else
                            for (final item in feed) _NotificationTile(item: item, onTap: () => _open(item)),
                          if (_tab != NotificationTab.system && _tab != NotificationTab.admin && s.inquiries.error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                              child: AgentErrorState(
                                compact: true,
                                message: 'Messages could not load: ${s.inquiries.error}',
                                onRetry: context.read<AgentWorkspaceCubit>().loadInquiries,
                              ),
                            ),
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

  Widget _tabChip(NotificationTab t) {
    final selected = t == _tab;
    return Material(
      color: selected ? AppColors.emeraldDark : AppColors.gray50,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.emeraldDark : AppColors.border)),
      child: InkWell(
        key: Key('agent-notif-tab-${t.name}'),
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _tab = t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            t.label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.gray600),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final (title, message) = switch (_tab) {
      NotificationTab.all => ('You are all caught up', 'New activity on your account will appear here.'),
      NotificationTab.messages => ('No messages', 'Buyer inquiries about your listings will appear here.'),
      NotificationTab.system => ('No updates yet', 'Bookings, escrow, payouts and subscription updates will appear here.'),
      NotificationTab.admin => ('No announcements', 'Announcements from Vektolux will appear here.'),
    };
    return AgentEmptyState(icon: Icons.notifications_none_rounded, title: title, message: message);
  }
}

class _NotificationTile extends StatelessWidget {
  final FeedItem item;
  final VoidCallback onTap;
  const _NotificationTile({required this.item, required this.onTap});

  (IconData, Color) _icon() {
    if (item.inquiry != null) return (Icons.chat_bubble_outline_rounded, AppColors.emeraldDark);
    final n = item.notification!;
    if (n.isAdminAnnouncement) return (Icons.campaign_outlined, const Color(0xFFEA580C));
    return switch (destinationFor(n)) {
      NotificationDestination.listings => (Icons.handshake_outlined, AgentTokens.rentBlue),
      NotificationDestination.deals => (Icons.account_balance_outlined, AgentTokens.deepGreen),
      NotificationDestination.earnings => (Icons.payments_outlined, AppColors.emeraldDark),
      NotificationDestination.subscription => (Icons.workspace_premium_outlined, AppColors.amberDark),
      NotificationDestination.bookings => (Icons.event_available_outlined, AgentTokens.rentBlue),
      NotificationDestination.none => (Icons.notifications_none_rounded, AppColors.gray600),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _icon();
    final hasDestination =
        item.inquiry != null || (item.notification != null && destinationFor(item.notification!) != NotificationDestination.none);
    return Material(
      color: item.unread ? AppColors.emeraldSurface.withValues(alpha: 0.55) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: item.unread ? FontWeight.w800 : FontWeight.w600,
                              color: AppColors.obsidian,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(formatListTime(item.time), style: const TextStyle(fontSize: 11, color: AppColors.gray400)),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.gray500, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (item.unread)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4, bottom: 6),
                      decoration: const BoxDecoration(color: AppColors.emeraldDark, shape: BoxShape.circle),
                    ),
                  if (hasDestination) const Icon(Icons.chevron_right_rounded, color: AppColors.gray400, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
