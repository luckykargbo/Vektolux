// lib/features/agent/presentation/views/agent_notifications_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent notifications (Notifications tab).
// Only real server events (notifications:getUserNotifications): new inquiries and messages,
// viewing requests and their answers, listing decisions (approved, rejected, removed),
// listing-agent invitations, escrow and payout updates, subscription and account decisions, new
// followers, and administrator announcements (broadcasts, which only an admin can create). Tabs:
// All · Messages · System · Admin. Read state, time and the unread count are the server's.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_earnings_screen.dart';
import 'agent_navigation.dart';
import 'agent_people_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<AgentWorkspaceCubit>();
    try {
      final list = await cubit.api.notifications();
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
      cubit.loadUnreadCount();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _markAllRead() async {
    try {
      await context.read<AgentWorkspaceCubit>().api.markAllNotificationsRead();
      await _load();
    } catch (e) {
      if (mounted) agentSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _open(AgentNotification n) async {
    final cubit = context.read<AgentWorkspaceCubit>();
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
    final scope = AgentShellScope.of(context);
    switch (destinationFor(n)) {
      case NotificationDestination.conversation:
        final id = n.deepLinkId;
        id == null ? scope.openTab(AgentTab.messages) : openConversation(context, id);
      case NotificationDestination.viewings:
        openViewings(context);
      case NotificationDestination.bookings:
        openBookings(context);
      case NotificationDestination.listings:
        scope.openTab(AgentTab.listings);
      case NotificationDestination.deals:
        openDeals(context);
      case NotificationDestination.earnings:
        pushAgentPage(context, const AgentEarningsScreen());
      case NotificationDestination.subscription:
        openSubscription(context);
      case NotificationDestination.followers:
        pushAgentPage(context, const AgentPeopleScreen(kind: PeopleKind.followers));
      case NotificationDestination.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final shown = items == null ? null : notificationsFor(items, _tab);
    final hasUnread = items?.any((n) => !n.read) ?? false;
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Notifications', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
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
                      Builder(builder: (_) {
                        final unread = items == null ? 0 : notificationsFor(items, t).where((n) => !n.read).length;
                        return AgentSegment(
                          key: Key('agent-notif-tab-${t.name}'),
                          label: unread > 0 && t != NotificationTab.all ? '${t.label} · $unread' : t.label,
                          selected: t == _tab,
                          onTap: () => setState(() => _tab = t),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.emerald,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (shown == null && _error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                          child: AgentErrorState(message: _error!, onRetry: _load),
                        )
                      else if (shown == null)
                        const AgentLoading()
                      else if (shown.isEmpty)
                        AgentEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: _tab == NotificationTab.all ? 'You are all caught up' : 'Nothing here yet',
                          message: _tab == NotificationTab.admin ? 'Announcements from Vektolux appear here.' : 'New activity appears here.',
                        )
                      else
                        for (final n in shown) _NotificationTile(item: n, onTap: () => _open(n)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AgentNotification item;
  final VoidCallback onTap;
  const _NotificationTile({required this.item, required this.onTap});

  (IconData, Color) _icon() {
    if (item.isAdminAnnouncement) return (Icons.campaign_outlined, const Color(0xFFEA580C));
    return switch (destinationFor(item)) {
      NotificationDestination.conversation => (Icons.chat_bubble_outline_rounded, AppColors.emeraldDark),
      NotificationDestination.viewings => (Icons.event_available_outlined, AgentTokens.rentBlue),
      NotificationDestination.bookings => (Icons.event_note_outlined, AgentTokens.rentBlue),
      NotificationDestination.listings => (Icons.home_work_outlined, AgentTokens.rentBlue),
      NotificationDestination.deals => (Icons.account_balance_outlined, AgentTokens.deepGreen),
      NotificationDestination.earnings => (Icons.payments_outlined, AppColors.emeraldDark),
      NotificationDestination.subscription => (Icons.workspace_premium_outlined, AppColors.amberDark),
      NotificationDestination.followers => (Icons.person_add_alt_1_outlined, const Color(0xFF7C3AED)),
      NotificationDestination.none => (Icons.verified_user_outlined, AppColors.gray600),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _icon();
    final unread = !item.read;
    final hasDestination = destinationFor(item) != NotificationDestination.none;
    return Material(
      color: unread ? AppColors.emeraldSurface.withValues(alpha: 0.55) : Colors.white,
      child: InkWell(
        key: Key('agent-notification-${item.id}'),
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
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              color: AppColors.obsidian,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(formatListTime(item.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.gray400)),
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
                  if (unread)
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
