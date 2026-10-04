// lib/features/agent/presentation/views/agent_home_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent dashboard (Home tab).
// Visual and compact: header, performance cards, live counts, earnings, next viewing, recent
// listings and quick actions. Every number is a server value; while one is loading or
// unavailable the card says so instead of showing a made-up figure.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_earnings_screen.dart';
import 'agent_navigation.dart';
import 'agent_people_screen.dart';
import 'agent_settings_screen.dart';
import 'agent_shell.dart';

class AgentHomeScreen extends StatelessWidget {
  const AgentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
            builder: (context, s) => RefreshIndicator(
              color: AppColors.emerald,
              onRefresh: cubit.loadAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, AgentTokens.gutter, 28),
                children: [
                  AgentProfileHeader(state: s, trailing: _headerButtons(context, s)),
                  if (s.status.postingBlockedReason != null) ...[
                    const SizedBox(height: 12),
                    _PostingBlockedStrip(reason: s.status.postingBlockedReason!),
                  ],
                  const SizedBox(height: 16),
                  _PerformanceCards(state: s),
                  const SizedBox(height: AgentTokens.gap),
                  _KpiStrip(state: s),
                  const SizedBox(height: AgentTokens.gap),
                  _EarningsCard(state: s),
                  ..._nextViewing(context, s),
                  const SizedBox(height: AgentTokens.sectionGap),
                  AgentSectionHeader(
                    title: 'Recent Listings',
                    actionLabel: 'See All',
                    onAction: () => AgentShellScope.of(context).openTab(AgentTab.listings),
                  ),
                  const SizedBox(height: 6),
                  _RecentListings(state: s),
                  const SizedBox(height: AgentTokens.sectionGap),
                  const AgentSectionHeader(title: 'Quick Actions'),
                  const SizedBox(height: 10),
                  _QuickActions(state: s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _headerButtons(BuildContext context, AgentWorkspaceState s) => [
        AgentHeaderButton(
          key: const Key('agent-home-notifications'),
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notifications',
          badgeCount: s.unreadCount,
          onTap: () => AgentShellScope.of(context).openTab(AgentTab.notifications),
        ),
        const SizedBox(width: 8),
        AgentHeaderButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onTap: () => pushAgentPage(context, const AgentSettingsScreen()),
        ),
      ];

  List<Widget> _nextViewing(BuildContext context, AgentWorkspaceState s) {
    final now = DateTime.now();
    final upcoming = (s.viewings.data ?? const <ViewingRequest>[]).where((v) => v.tabAt(now) == ViewingTab.upcoming).toList();
    if (upcoming.isEmpty) return const [];
    final next = upcoming.first;
    return [
      const SizedBox(height: AgentTokens.gap),
      AgentCard(
        key: const Key('agent-next-viewing'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => openViewings(context),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.infoLight, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.event_available_rounded, color: AgentTokens.rentBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(next.listingTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                  Text(
                    '${next.typeLabel} · ${DateFormat('EEE d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(next.startTime))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                  ),
                ],
              ),
            ),
            if (upcoming.length > 1) ...[
              const SizedBox(width: 8),
              AgentPill(label: '+${upcoming.length - 1}', background: AppColors.infoLight, foreground: AgentTokens.rentBlue),
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
          ],
        ),
      ),
    ];
  }
}

/// Photo, name, verified badge (server-computed), role and subscription label.
class AgentProfileHeader extends StatelessWidget {
  final AgentWorkspaceState state;
  final List<Widget> trailing;
  final double avatarRadius;

  const AgentProfileHeader({super.key, required this.state, this.trailing = const [], this.avatarRadius = 27});

  @override
  Widget build(BuildContext context) {
    final user = AgentShellScope.of(context).user;
    final label = subscriptionLabel(state.status, state.subscription);
    final avatar = state.profile.data?.avatarUrl ?? user.avatarUrl;
    return Row(
      children: [
        VektoluxAvatar(avatarUrl: avatar, name: user.name, radius: avatarRadius, borderWidth: 0),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user.name.trim().isEmpty ? 'Your name' : user.name,
                      key: const Key('agent-header-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                    ),
                  ),
                  if (state.status.verifiedAgent) ...[
                    const SizedBox(width: 5),
                    const VerifiedBadge(
                      key: Key('agent-verified-badge'),
                      customTooltip: 'Verified Real Estate Agent',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              const Text('Real Estate Agent', style: TextStyle(fontSize: 12.5, color: AppColors.gray500, fontWeight: FontWeight.w500)),
              if (label != null) ...[
                const SizedBox(height: 6),
                AgentPill(
                  key: const Key('agent-subscription-label'),
                  label: label,
                  background: AppColors.amberSurface,
                  foreground: AppColors.amberDark,
                  icon: Icons.workspace_premium_rounded,
                ),
              ],
            ],
          ),
        ),
        ...trailing,
      ],
    );
  }
}

class _PostingBlockedStrip extends StatelessWidget {
  final String reason;
  const _PostingBlockedStrip({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('agent-posting-blocked'),
      color: AppColors.amberSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showPostingBlockedSheet(context, reason),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              const Icon(Icons.lock_clock_outlined, color: AppColors.amberDark, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Posting paused · subscription needed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
              ),
              TextButton(
                onPressed: () => openSubscription(context),
                style: TextButton.styleFrom(foregroundColor: AppColors.amberDark, minimumSize: const Size(44, 32)),
                child: const Text('Plans', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PerformanceCards extends StatelessWidget {
  final AgentWorkspaceState state;
  const _PerformanceCards({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    final listings = state.portfolio;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _GreenStatCard(
              key: const Key('agent-total-listings'),
              icon: Icons.home_work_outlined,
              label: 'Total Listings',
              value: listings?.length,
              loading: listings == null && state.ownListings.error == null,
              error: listings == null ? state.ownListings.error : null,
              colors: const [AgentTokens.deepGreen, AppColors.emeraldDark],
              onTap: () => AgentShellScope.of(context).openTab(AgentTab.listings),
              onRetry: cubit.loadListings,
            ),
          ),
          const SizedBox(width: AgentTokens.gap),
          Expanded(
            child: _GreenStatCard(
              key: const Key('agent-active-deals'),
              icon: Icons.handshake_outlined,
              label: 'Active Deals',
              value: state.activeDeals,
              loading: state.deals.isPending,
              error: state.deals.data == null ? state.deals.error : null,
              colors: const [AppColors.emeraldDark, AppColors.emerald],
              onTap: () => openDeals(context),
              onRetry: cubit.loadDeals,
            ),
          ),
        ],
      ),
    );
  }
}

class _GreenStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? value;
  final bool loading;
  final String? error;
  final List<Color> colors;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  const _GreenStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.loading,
    required this.error,
    required this.colors,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final Widget valueWidget;
    if (value != null) {
      valueWidget = Text(formatCount(value!), style: const TextStyle(color: white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1));
    } else if (loading) {
      valueWidget = const SizedBox(
        height: 31,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: white)),
        ),
      );
    } else {
      valueWidget = const Text('—', style: TextStyle(color: white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AgentTokens.radius),
        onTap: error != null ? onRetry : onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AgentTokens.radius),
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: white, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 2, style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              valueWidget,
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      error != null ? 'Retry' : 'View All',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: white.withValues(alpha: 0.92), fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(error != null ? Icons.refresh_rounded : Icons.arrow_forward_rounded, color: white, size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four live counts: active and unpublished listings, unread client messages, followers.
class _KpiStrip extends StatelessWidget {
  final AgentWorkspaceState state;
  const _KpiStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final scope = AgentShellScope.of(context);
    final listings = state.portfolio;
    final items = <(Key, IconData, Color, int?, String, VoidCallback)>[
      (
        const Key('agent-kpi-active'),
        Icons.check_circle_outline_rounded,
        AppColors.emeraldDark,
        listings?.where((l) => l.liveStatus == ListingLiveStatus.live).length,
        'Active',
        () => scope.openTab(AgentTab.listings),
      ),
      (
        const Key('agent-kpi-unpublished'),
        Icons.visibility_off_outlined,
        AppColors.amberDark,
        listings?.where((l) => !l.isPublished).length,
        'Unpublished',
        () => scope.openTab(AgentTab.listings),
      ),
      (
        const Key('agent-kpi-messages'),
        Icons.mark_chat_unread_outlined,
        AgentTokens.rentBlue,
        state.conversations.data == null ? null : state.unreadMessages,
        'Unread',
        () => scope.openTab(AgentTab.messages),
      ),
      (
        const Key('agent-kpi-followers'),
        Icons.people_alt_outlined,
        AppColors.obsidianSoft,
        state.profile.data?.followers,
        'Followers',
        () => pushAgentPage(context, const AgentPeopleScreen(kind: PeopleKind.followers)),
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AgentCard(
                key: items[i].$1,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                onTap: items[i].$6,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[i].$2, color: items[i].$3, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      items[i].$4 == null ? '—' : formatCount(items[i].$4!),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(items[i].$5,
                          maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.gray500, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// All-time earnings (sum of completed payouts credited to the wallet, from the server).
/// The backend has no per-month figure, so none is shown or derived.
class _EarningsCard extends StatelessWidget {
  final AgentWorkspaceState state;
  const _EarningsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final e = state.earnings;
    final Widget value;
    String? subtitle;
    if (e.data != null) {
      value = Text(
        formatMoney(e.data!.totalEarned, currency: e.data!.currency, forceCents: true),
        key: const Key('agent-earnings-total'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.obsidian),
      );
      final n = e.data!.count;
      subtitle = '$n payout${n == 1 ? '' : 's'}';
    } else if (e.error != null) {
      value = const Text('Unavailable · tap to retry', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray500));
    } else {
      value = const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.emerald)),
      );
    }
    return AgentCard(
      onTap: () => e.error != null && e.data == null
          ? context.read<AgentWorkspaceCubit>().loadEarnings()
          : pushAgentPage(context, const AgentEarningsScreen()),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.emeraldSurface, shape: BoxShape.circle),
            child: const Icon(Icons.payments_outlined, color: AppColors.emeraldDark, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Earnings', style: TextStyle(fontSize: 12.5, color: AppColors.gray500, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                value,
              ],
            ),
          ),
          if (subtitle != null)
            AgentPill(label: subtitle, background: AppColors.emeraldSurface, foreground: AppColors.emeraldDark),
          const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
        ],
      ),
    );
  }
}

class _RecentListings extends StatelessWidget {
  final AgentWorkspaceState state;
  const _RecentListings({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    final listings = state.portfolio;
    if (listings == null) {
      if (state.ownListings.error != null) {
        return AgentErrorState(message: state.ownListings.error!, onRetry: cubit.loadListings);
      }
      return const AgentLoading(label: 'Loading your listings…');
    }
    if (listings.isEmpty) {
      final canPost = state.status.postingBlockedReason == null;
      return AgentCard(
        child: AgentEmptyState(
          icon: Icons.home_work_outlined,
          title: 'No listings yet',
          message: canPost ? 'Create your first property listing.' : 'Posting opens with an active subscription.',
          actionLabel: canPost ? 'Add Listing' : null,
          onAction: canPost ? () => openAddListing(context) : null,
        ),
      );
    }
    final recent = listings.take(6).toList();
    final inquiries = state.inquiriesByListing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - AgentTokens.gap) / 2;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const SizedBox(width: AgentTokens.gap),
                  SizedBox(width: cardWidth, child: AgentListingTile(listing: recent[i], inquiries: inquiries[recent[i].id] ?? 0)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Vertical listing card (dashboard).
class AgentListingTile extends StatelessWidget {
  final AgentListing listing;
  final int inquiries;
  const AgentListingTile({super.key, required this.listing, this.inquiries = 0});

  @override
  Widget build(BuildContext context) {
    return AgentCard(
      padding: const EdgeInsets.all(8),
      onTap: () => openListingDetail(context, listing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AgentListingImage(listing: listing, aspectRatio: 1.45),
          const SizedBox(height: 8),
          Text(
            listing.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 3),
          AgentLocationLine(text: listing.publicLocation),
          const SizedBox(height: 5),
          Text(
            listing.priceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.obsidian),
          ),
          const SizedBox(height: 5),
          AgentListingSpecs(listing: listing),
          const Spacer(),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AgentStatusPill(status: listing.liveStatus),
              if (inquiries > 0) AgentInquiryChip(count: inquiries),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final AgentWorkspaceState state;
  const _QuickActions({required this.state});

  @override
  Widget build(BuildContext context) {
    final scope = AgentShellScope.of(context);
    final actions = <(IconData, String, VoidCallback, int)>[
      (Icons.add_home_outlined, 'Add Property', () => openAddListing(context), 0),
      (Icons.home_work_outlined, 'My Listings', () => scope.openTab(AgentTab.listings), 0),
      (Icons.chat_bubble_outline_rounded, 'Messages', () => scope.openTab(AgentTab.messages), state.unreadMessages),
      (Icons.event_available_outlined, 'Viewings', () => openViewings(context), state.upcomingViewingsAt(DateTime.now())),
      (Icons.notifications_none_rounded, 'Notifications', () => scope.openTab(AgentTab.notifications), state.unreadCount),
    ];
    // Five actions: all built (a plain scrolling row), so every one is reachable at any width.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            SizedBox(
              width: 84,
              height: 92,
              child: AgentCard(
                key: Key('agent-quick-${actions[i].$2}'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                onTap: actions[i].$3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.emeraldSurface, borderRadius: BorderRadius.circular(12)),
                          child: Icon(actions[i].$1, color: AppColors.emeraldDark, size: 22),
                        ),
                        if (actions[i].$4 > 0) Positioned(right: -6, top: -6, child: AgentCountBadge(count: actions[i].$4)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        actions[i].$2,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
