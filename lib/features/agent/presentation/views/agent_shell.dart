// lib/features/agent/presentation/views/agent_shell.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent workspace shell.
// Five destinations — Home, Listings, Messages, Notifications, Profile — shown only to an
// administrator-approved Real Estate Agent (decided by MainNavigationShell from the server's
// professional status). Showing these screens grants nothing: every action is authorised again
// by the server.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../data/agent_api.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_home_screen.dart';
import 'agent_listings_screen.dart';
import 'agent_messages_screen.dart';
import 'agent_notifications_screen.dart';
import 'agent_profile_screen.dart';

/// Tab indexes of the agent workspace.
class AgentTab {
  AgentTab._();
  static const int home = 0;
  static const int listings = 1;
  static const int messages = 2;
  static const int notifications = 3;
  static const int profile = 4;
}

/// What every agent screen (including pushed pages) can reach: the signed-in user, tab switching
/// and the standard client view.
class AgentShellScope extends InheritedWidget {
  final UserEntity user;
  final ConvexClientWrapper convexClient;
  final ValueChanged<int> openTab;
  final VoidCallback openClientView;

  /// The route that shows the shell (pages pushed on top pop back to it to switch tabs).
  final Route<dynamic>? shellRoute;

  const AgentShellScope({
    super.key,
    required this.user,
    required this.convexClient,
    required this.openTab,
    required this.openClientView,
    this.shellRoute,
    required super.child,
  });

  static AgentShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AgentShellScope>();
    assert(scope != null, 'AgentShellScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AgentShellScope oldWidget) => user != oldWidget.user;
}

/// Pushes [page] keeping access to the agent workspace data and scope.
Future<T?> pushAgentPage<T>(BuildContext context, Widget page) {
  final cubit = context.read<AgentWorkspaceCubit>();
  final scope = AgentShellScope.of(context);
  return Navigator.of(context).push<T>(MaterialPageRoute(
    builder: (_) => AgentShellScope(
      user: scope.user,
      convexClient: scope.convexClient,
      openTab: (i) {
        final home = scope.shellRoute;
        Navigator.of(context).popUntil((r) => home == null ? r.isFirst : r == home);
        scope.openTab(i);
      },
      openClientView: scope.openClientView,
      shellRoute: scope.shellRoute,
      child: BlocProvider.value(value: cubit, child: page),
    ),
  ));
}

class AgentShell extends StatefulWidget {
  final UserEntity user;
  final ProfessionalStatus status;
  final ConvexClientWrapper convexClient;

  /// Called when a refreshed server status no longer grants the agent workspace
  /// (for example the role was suspended meanwhile).
  final ValueChanged<ProfessionalStatus> onStatusChanged;

  /// Shows the standard client app (a view choice, never a permission).
  final VoidCallback onOpenClientView;
  final int initialTab;

  const AgentShell({
    super.key,
    required this.user,
    required this.status,
    required this.convexClient,
    required this.onStatusChanged,
    required this.onOpenClientView,
    this.initialTab = AgentTab.home,
  });

  @override
  State<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends State<AgentShell> {
  late final AgentWorkspaceCubit _cubit;
  late int _index;
  late final Set<int> _activated;
  DateTime _lastBadgeRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab;
    _activated = {_index};
    _cubit = AgentWorkspaceCubit(
      api: AgentApi(client: widget.convexClient, userId: widget.user.id, sessionToken: widget.user.sessionToken),
      status: widget.status,
    )..loadAll();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _openTab(int index) {
    if (index < 0 || index > 4) return;
    setState(() {
      _index = index;
      _activated.add(index);
    });
    // Keep the badges current without polling: refresh them at most every 20 s on navigation.
    final now = DateTime.now();
    if (now.difference(_lastBadgeRefresh) > const Duration(seconds: 20)) {
      _lastBadgeRefresh = now;
      _cubit.loadUnreadCount();
      _cubit.loadInquiries();
    }
  }

  Widget _tab(int index, Widget Function() build) => _activated.contains(index) ? build() : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocListener<AgentWorkspaceCubit, AgentWorkspaceState>(
        listenWhen: (a, b) => a.status != b.status,
        listener: (context, s) {
          if (s.status.access != AgentAccess.approved) widget.onStatusChanged(s.status);
        },
        child: AgentShellScope(
          user: widget.user,
          convexClient: widget.convexClient,
          openTab: _openTab,
          openClientView: widget.onOpenClientView,
          shellRoute: ModalRoute.of(context),
          child: Scaffold(
            backgroundColor: AgentTokens.page,
            body: IndexedStack(
              index: _index,
              children: [
                _tab(AgentTab.home, () => const AgentHomeScreen()),
                _tab(AgentTab.listings, () => const AgentListingsScreen()),
                _tab(AgentTab.messages, () => const AgentMessagesScreen()),
                _tab(AgentTab.notifications, () => const AgentNotificationsScreen()),
                _tab(AgentTab.profile, () => const AgentProfileScreen()),
              ],
            ),
            bottomNavigationBar: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
              buildWhen: (a, b) => a.pendingInquiries != b.pendingInquiries || a.unreadCount != b.unreadCount,
              builder: (context, s) => _AgentNavBar(
                index: _index,
                onTap: _openTab,
                messagesDot: s.pendingInquiries > 0,
                notificationsDot: s.unreadCount > 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final bool messagesDot;
  final bool notificationsDot;

  const _AgentNavBar({required this.index, required this.onTap, required this.messagesDot, required this.notificationsDot});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: AgentTokens.maxTextScale,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _item(AgentTab.home, 'Home', Icons.home_outlined, Icons.home_rounded),
                _item(AgentTab.listings, 'Listings', Icons.home_work_outlined, Icons.home_work_rounded),
                _item(AgentTab.messages, 'Messages', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
                    dot: messagesDot),
                _item(AgentTab.notifications, 'Notifications', Icons.notifications_none_rounded,
                    Icons.notifications_rounded,
                    dot: notificationsDot),
                _item(AgentTab.profile, 'Profile', Icons.person_outline_rounded, Icons.person_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i, String label, IconData icon, IconData activeIcon, {bool dot = false}) {
    final selected = index == i;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          key: Key('agent-nav-$i'),
          onTap: () => onTap(i),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.emeraldSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(selected ? activeIcon : icon, size: 22, color: selected ? AppColors.emeraldDark : AppColors.gray400),
                      if (dot) const Positioned(right: -3, top: -2, child: AgentCountBadge()),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.emeraldDark : AppColors.gray500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
