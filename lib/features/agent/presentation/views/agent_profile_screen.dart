// lib/features/agent/presentation/views/agent_profile_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent profile (Profile tab).
// Photo, real name, verified badge (server-computed), role, subscription label, real counts
// (listings, active deals, followers) and links. Account details are edited only through the
// existing Account screen; approval, badge and permissions cannot be changed from here.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_earnings_screen.dart';
import 'agent_home_screen.dart';
import 'agent_navigation.dart';
import 'agent_people_screen.dart';
import 'agent_settings_screen.dart';
import 'agent_shell.dart';

class AgentProfileScreen extends StatelessWidget {
  const AgentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    final scope = AgentShellScope.of(context);
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
                padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 14, AgentTokens.gutter, 28),
                children: [
                  AgentProfileHeader(
                    state: s,
                    avatarRadius: 30,
                    trailing: [
                      AgentHeaderButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit profile',
                        onTap: () => openAccountSettings(context),
                      ),
                      const SizedBox(width: 8),
                      AgentHeaderButton(
                        icon: Icons.settings_outlined,
                        tooltip: 'Settings',
                        onTap: () => pushAgentPage(context, const AgentSettingsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _StatsRow(state: s),
                  const SizedBox(height: 18),
                  AgentCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        _MenuTile(
                          icon: Icons.home_work_outlined,
                          label: 'My Listings',
                          onTap: () => scope.openTab(AgentTab.listings),
                        ),
                        _MenuTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Messages',
                          onTap: () => scope.openTab(AgentTab.messages),
                        ),
                        _MenuTile(
                          icon: Icons.people_outline_rounded,
                          label: 'Followers',
                          onTap: () => pushAgentPage(context, const AgentPeopleScreen(kind: PeopleKind.followers)),
                        ),
                        _MenuTile(
                          icon: Icons.person_add_alt_outlined,
                          label: 'Following',
                          onTap: () => pushAgentPage(context, const AgentPeopleScreen(kind: PeopleKind.following)),
                        ),
                        _MenuTile(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Earnings & Payouts',
                          onTap: () => pushAgentPage(context, const AgentEarningsScreen()),
                        ),
                        _MenuTile(
                          icon: Icons.support_agent_rounded,
                          label: 'Support',
                          onTap: () => showAgentSupportSheet(context),
                        ),
                        _MenuTile(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          onTap: () => pushAgentPage(context, const AgentSettingsScreen()),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: TextButton.icon(
                      key: const Key('agent-logout'),
                      onPressed: () => confirmAgentLogout(context),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.emeraldDark,
                        backgroundColor: AppColors.emeraldSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppColors.emerald.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final AgentWorkspaceState state;
  const _StatsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    final stats = <(String, int?, bool, VoidCallback)>[
      ('Listings', state.portfolio?.length, state.ownListings.data == null && state.ownListings.error != null, cubit.loadListings),
      ('Active Deals', state.activeDeals, state.deals.data == null && state.deals.error != null, cubit.loadDeals),
      ('Followers', state.profile.data?.followers, state.profile.data == null && state.profile.error != null, cubit.loadProfile),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: AgentCard(
                key: Key('agent-stat-${stats[i].$1}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                onTap: stats[i].$3 ? stats[i].$4 : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    stats[i].$2 != null
                        ? Text(formatCount(stats[i].$2!),
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.obsidian))
                        : stats[i].$3
                            ? const Icon(Icons.refresh_rounded, color: AppColors.gray400)
                            : const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.emerald)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(stats[i].$1,
                          maxLines: 1, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500, fontWeight: FontWeight.w600)),
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

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;

  const _MenuTile({required this.icon, required this.label, required this.onTap, this.last = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('agent-menu-$label'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.gray100))),
        child: Row(
          children: [
            Icon(icon, color: AppColors.obsidianSoft, size: 21),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.obsidian)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
          ],
        ),
      ),
    );
  }
}
