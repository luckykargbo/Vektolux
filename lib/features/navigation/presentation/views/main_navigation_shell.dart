// lib/features/navigation/presentation/views/main_navigation_shell.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Super App Persistent Bottom Navigation Shell
// Coordinates 5 core verticals: Home Discovery, Explore (Social Feed),
// Real Estate Marketplace, Auto Marketplace, and Account Profile.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../agent/domain/agent_models.dart';
import '../../../agent/presentation/views/agent_pending_screen.dart';
import '../../../agent/presentation/views/agent_shell.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../home/presentation/views/client_home_screen.dart';
import '../../../mobility/presentation/views/auto_marketplace_screen.dart';
import '../../../explore/presentation/views/explore_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';
import '../../../real_estate/presentation/views/real_estate_marketplace_screen.dart';
import '../widgets/client_onboarding_tour_modal.dart';

class MainNavigationShell extends StatefulWidget {
  final int initialTabIndex;

  const MainNavigationShell({
    super.key,
    this.initialTabIndex = 0,
  });

  /// Static helper allowing any child widget in the tree to switch tabs.
  static void switchToTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainNavigationShellState>();
    state?.setTab(index);
  }

  /// Replay the first-time guided onboarding tour anytime from settings or help
  static void showAppTour(BuildContext context) {
    ClientOnboardingTourModal.show(context, onFinish: () {});
  }

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

/// Which workspace the signed-in account sees. Chosen from the SERVER's professional status
/// (subscriptions:getMyProfessionalStatus); choosing a view never grants a permission.
enum _ShellRoute { standard, agent, agentAwaiting, checking, accessError }

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;
  late final Set<int> _activatedTabs;
  // Feature flag: toggle to true to re-enable automatic first-time onboarding walkthrough
  // TODO: Re-enable guided tour when ready to redesign
  static const bool _enableAutoGuidedTour = false;
  static bool _hasShownTourGlobally = false;

  // ── Role-specific workspace (server-authoritative) ────────────────
  ProfessionalStatus? _proStatus;
  String? _statusUserId;
  bool _statusResolved = false; // a status was read for _statusUserId
  String? _statusError;
  bool _clientView = false; // session-only view choice of an agent / applicant
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _activatedTabs = {_currentIndex};
    _loadProfessionalStatus(context.read<AuthBloc>().state.user);
    _ready = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowTour();
    });
  }

  void _apply(VoidCallback fn) => _ready && mounted ? setState(fn) : fn();

  /// Reads the caller's professional status. Returns an error message, or null on success.
  Future<String?> _loadProfessionalStatus(UserEntity? user) async {
    final forUser = user?.id;
    if (forUser != _statusUserId) {
      _apply(() {
        _statusUserId = forUser;
        _proStatus = null;
        _statusResolved = false;
        _statusError = null;
        _clientView = false;
      });
    } else if (!_statusResolved && _statusError != null) {
      _apply(() => _statusError = null); // a retry shows the "checking" view again
    }
    // Administrators keep their existing tools; there is nothing to read for a signed-out user.
    if (user == null || user.role == UserRole.admin) return null;
    final token = user.sessionToken;
    final res = await context.read<ConvexClientWrapper>().query(
      'subscriptions:getMyProfessionalStatus',
      args: {if (token != null && token.isNotEmpty) 'sessionToken': token},
    );
    if (!mounted || _statusUserId != forUser) return null;
    if (res.success) {
      _apply(() {
        _proStatus = res.value is Map ? ProfessionalStatus.fromMap(Map<String, dynamic>.from(res.value as Map)) : null;
        _statusResolved = true;
        _statusError = null;
      });
      return null;
    }
    final message = res.errorMessage ?? 'The server could not be reached.';
    if (message.contains('Could not find public function')) {
      // The connected backend does not have this function yet (not deployed): there is no
      // professional status to apply, so the account keeps the standard app exactly as before.
      _apply(() {
        _proStatus = null;
        _statusResolved = true;
        _statusError = null;
      });
      return null;
    }
    _apply(() => _statusError = message);
    return message;
  }

  _ShellRoute _routeFor(UserEntity? user) {
    if (user == null || _clientView) return _ShellRoute.standard;
    if (_statusResolved) {
      return switch (_proStatus?.access ?? AgentAccess.none) {
        AgentAccess.approved => _ShellRoute.agent,
        AgentAccess.awaitingApproval => _ShellRoute.agentAwaiting,
        AgentAccess.none => _ShellRoute.standard,
      };
    }
    // Not resolved yet: buyers get the standard app at once; an account that may be an agent
    // (the app maps both agent and property-owner accounts to UserRole.agent) waits for the server.
    if (user.role != UserRole.agent) return _ShellRoute.standard;
    return _statusError != null ? _ShellRoute.accessError : _ShellRoute.checking;
  }

  void _openClientView() => setState(() => _clientView = true);

  void _returnToAgentView() {
    setState(() => _clientView = false);
    _loadProfessionalStatus(context.read<AuthBloc>().state.user);
  }

  void _checkAndShowTour() {
    // TODO: Re-enable guided tour when ready to redesign
    if (!_enableAutoGuidedTour) return;
    if (_hasShownTourGlobally || !mounted) return;
    _hasShownTourGlobally = true;
    ClientOnboardingTourModal.show(context, onFinish: () {});
  }

  void setTab(int index) {
    if (index >= 0 && index < 5) {
      setState(() {
        _currentIndex = index;
        _activatedTabs.add(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final convexClient = context.read<ConvexClientWrapper>();

    return BlocConsumer<AuthBloc, AuthState>(
      // Another account (or a changed role) gets its workspace decided again by the server.
      listenWhen: (prev, curr) => prev.user?.id != curr.user?.id || prev.user?.role != curr.user?.role,
      listener: (context, authState) => _loadProfessionalStatus(authState.user),
      builder: (context, authState) {
        final user = authState.user;
        switch (_routeFor(user)) {
          case _ShellRoute.agent:
            return AgentShell(
              key: ValueKey('agent-shell-${user!.id}'),
              user: user,
              status: _proStatus!,
              convexClient: convexClient,
              onStatusChanged: (status) => setState(() => _proStatus = status),
              onOpenClientView: _openClientView,
            );
          case _ShellRoute.agentAwaiting:
            return AgentPendingScreen(
              user: user!,
              status: _proStatus!,
              onRefresh: () => _loadProfessionalStatus(user),
              onBrowseAsClient: _openClientView,
            );
          case _ShellRoute.checking:
            return const AgentAccessCheckView();
          case _ShellRoute.accessError:
            return AgentAccessErrorView(
              message: _statusError ?? '',
              onRetry: () => _loadProfessionalStatus(user),
              onContinue: _openClientView,
            );
          case _ShellRoute.standard:
            break;
        }
        final currentUserId = user?.id ?? '';

        final pages = [
          // 0: Home Super App Discovery
          _activatedTabs.contains(0)
              ? ClientHomeScreen(convexClient: convexClient)
              : const SizedBox.shrink(),

          // 1: Explore Discovery Feed & Search
          _activatedTabs.contains(1)
              ? ExploreScreen(convexClient: convexClient)
              : const SizedBox.shrink(),

          // 2: Real Estate Vertical Marketplace
          _activatedTabs.contains(2)
              ? RealEstateMarketplaceScreen(convexClient: convexClient)
              : const SizedBox.shrink(),

          // 3: Auto Market & Car Rentals + Delivery Van Bookings
          _activatedTabs.contains(3)
              ? AutoMarketplaceScreen(convexClient: convexClient)
              : const SizedBox.shrink(),

          // 4: Account & Vendor Profile
          _activatedTabs.contains(4)
              ? ProfileScreen(currentUserId: currentUserId)
              : const SizedBox.shrink(),
        ];

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
          bottomNavigationBar: _withAgentReturnBar(Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            // Respects the home-indicator inset; labels capped at 1.15× text scale so five equal
            // tabs always fit on one line.
            child: SafeArea(
              top: false,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    _buildNavItem(
                      index: 0,
                      label: 'Home',
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                    ),
                    _buildNavItem(
                      index: 1,
                      label: 'Explore',
                      icon: Icons.explore_outlined,
                      activeIcon: Icons.explore_rounded,
                    ),
                    _buildNavItem(
                      index: 2,
                      label: 'Real Estate',
                      icon: Icons.apartment_outlined,
                      activeIcon: Icons.apartment_rounded,
                    ),
                    _buildNavItem(
                      index: 3,
                      label: 'Auto Market',
                      icon: Icons.directions_car_outlined,
                      activeIcon: Icons.directions_car_filled_rounded,
                    ),
                    _buildNavItem(
                      index: 4,
                      label: 'Account',
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                    ),
                  ],
                ),
              ),
              ),
            ),
          )),
        );
      },
    );
  }

  /// While an approved agent (or an applicant) browses the standard app, a slim bar above the
  /// tabs leads back to their workspace. Everyone else gets the tab bar unchanged.
  Widget _withAgentReturnBar(Widget navBar) {
    final access = _proStatus?.access ?? AgentAccess.none;
    if (!_clientView || !_statusResolved || access == AgentAccess.none) return navBar;
    final approved = access == AgentAccess.approved;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.obsidian,
          child: InkWell(
            key: const Key('return-to-agent-workspace'),
            onTap: _returnToAgentView,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.real_estate_agent_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      approved ? 'Viewing Vektolux as a client' : 'Your agent application',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    approved ? 'Agent dashboard' : 'View status',
                    style: const TextStyle(color: AppColors.emeraldLight, fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.emeraldLight, size: 18),
                ],
              ),
            ),
          ),
        ),
        navBar,
      ],
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = _currentIndex == index;

    // Five equal-width tabs (previously sized to their content, so long labels crowded the bar).
    return Expanded(
      child: InkWell(
      onTap: () => setTab(index),
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
                color: isSelected
                    ? AppColors.emeraldSurface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 22,
                color: isSelected ? AppColors.emeraldDark : AppColors.gray400,
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
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.emeraldDark : AppColors.gray500,
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
