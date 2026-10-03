// lib/features/agent/presentation/views/agent_home_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent dashboard (Home tab).
// Header (photo, real name, verified badge only when the server computes it, role,
// subscription label only when active, real unread count), performance cards, earnings,
// recent listings and quick actions. Every number is a server value; while one is loading or
// unavailable the card says so instead of showing a made-up figure.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_analytics_screen.dart';
import 'agent_earnings_screen.dart';
import 'agent_navigation.dart';
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
                    const SizedBox(height: 14),
                    _PostingBlockedBanner(reason: s.status.postingBlockedReason!),
                  ],
                  const SizedBox(height: 18),
                  _PerformanceCards(state: s),
                  const SizedBox(height: AgentTokens.gap),
                  _EarningsCard(state: s),
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
                  const _QuickActions(),
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
      crossAxisAlignment: CrossAxisAlignment.center,
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
                      customTooltip: 'Verified Real Estate Agent: approved by Vektolux with an active subscription',
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

class _PostingBlockedBanner extends StatelessWidget {
  final String reason;
  const _PostingBlockedBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('agent-posting-blocked'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amberSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_outlined, color: AppColors.amberDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reason, style: const TextStyle(fontSize: 12.5, color: AppColors.obsidian, height: 1.35)),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => openSubscription(context),
            style: TextButton.styleFrom(foregroundColor: AppColors.amberDark, minimumSize: const Size(44, 36)),
            child: const Text('Plans', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
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
    Widget valueWidget;
    if (value != null) {
      valueWidget = Text(formatCount(value!),
          style: const TextStyle(color: white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1));
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
                        maxLines: 2,
                        style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2)),
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
                      error != null ? 'Unavailable · Retry' : 'View All',
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

/// All-time earnings (sum of completed payouts credited to the wallet, from the server).
/// The backend has no per-month figure, so none is shown or derived.
class _EarningsCard extends StatelessWidget {
  final AgentWorkspaceState state;
  const _EarningsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final e = state.earnings;
    Widget value;
    String subtitle;
    if (e.data != null) {
      value = Text(
        formatMoney(e.data!.totalEarned, currency: e.data!.currency, forceCents: true),
        key: const Key('agent-earnings-total'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.obsidian),
      );
      final n = e.data!.count;
      subtitle = n == 0 ? 'No completed payouts yet' : '$n completed payout${n == 1 ? '' : 's'} to your wallet';
    } else if (e.error != null) {
      value = const Text('Unavailable', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.gray500));
      subtitle = 'Tap to retry';
    } else {
      value = const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.emerald)),
      );
      subtitle = 'Loading…';
    }
    return AgentCard(
      onTap: () => e.error != null && e.data == null
          ? context.read<AgentWorkspaceCubit>().loadEarnings()
          : pushAgentPage(context, const AgentEarningsScreen()),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: AppColors.emeraldSurface, shape: BoxShape.circle),
            child: const Icon(Icons.payments_outlined, color: AppColors.emeraldDark, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Earnings', style: TextStyle(fontSize: 12.5, color: AppColors.gray500, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                value,
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
              ],
            ),
          ),
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
      final reason = state.status.postingBlockedReason;
      return AgentCard(
        child: AgentEmptyState(
          icon: Icons.home_work_outlined,
          title: 'No listings yet',
          message: reason ?? 'Add your first property to start receiving buyer inquiries.',
          actionLabel: reason == null ? 'Add Listing' : null,
          onAction: reason == null ? () => openAddListing(context) : null,
        ),
      );
    }
    final recent = listings.take(6).toList();
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
                  SizedBox(width: cardWidth, child: AgentListingTile(listing: recent[i])),
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
  const AgentListingTile({super.key, required this.listing});

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
          Align(alignment: Alignment.centerLeft, child: AgentStatusPill(status: listing.liveStatus)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final scope = AgentShellScope.of(context);
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.add_home_outlined, 'Add Listing', () => openAddListing(context)),
      (Icons.chat_bubble_outline_rounded, 'Messages', () => scope.openTab(AgentTab.messages)),
      (Icons.insights_rounded, 'Analytics', () => pushAgentPage(context, const AgentAnalyticsScreen())),
      (Icons.support_agent_rounded, 'Support', () => showAgentSupportSheet(context)),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: AgentCard(
                key: Key('agent-quick-${actions[i].$2}'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                onTap: actions[i].$3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.emeraldSurface, borderRadius: BorderRadius.circular(12)),
                      child: Icon(actions[i].$1, color: AppColors.emeraldDark, size: 22),
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
