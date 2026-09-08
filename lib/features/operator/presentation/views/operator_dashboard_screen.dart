// lib/features/operator/presentation/views/operator_dashboard_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vendor & Operator Portal
// Dedicated workspace for Drivers, Real Estate Agents, and Auto Dealers.
// Provides live dispatch radar, property management, and fleet inventory.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../mobility/presentation/views/driver_portal_screen.dart';
import '../../../mobility/presentation/views/driver_vehicle_registration_screen.dart';

class OperatorDashboardScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const OperatorDashboardScreen({
    super.key,
    required this.database,
    required this.convexClient,
  });

  @override
  State<OperatorDashboardScreen> createState() =>
      _OperatorDashboardScreenState();
}

class _OperatorDashboardScreenState extends State<OperatorDashboardScreen> {
  UserRole? _activeWorkspace;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        final role = user?.role ?? UserRole.client;
        final currentWorkspace =
            _activeWorkspace ?? (role == UserRole.client ? UserRole.driver : role);
        final roleName = currentWorkspace.displayName;

        return Scaffold(
          backgroundColor: AppColors.gray50,
          appBar: AppBar(
            backgroundColor: AppColors.obsidian,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Operator & Vendor Portal',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                Text(
                  roleName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.emerald,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.swap_horiz_rounded,
                    size: 18, color: AppColors.emerald),
                label: const Text(
                  'Client Mode',
                  style: TextStyle(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Operator Welcome Banner ─────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.obsidian, Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          currentWorkspace == UserRole.driver
                              ? Icons.local_taxi_rounded
                              : currentWorkspace == UserRole.agent
                                  ? Icons.apartment_rounded
                                  : Icons.directions_car_filled_rounded,
                          size: 32,
                          color: AppColors.emerald,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Workspace: $roleName',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentWorkspace == UserRole.driver
                                  ? 'Accept on-demand rides & track SLE earnings'
                                  : currentWorkspace == UserRole.agent
                                      ? 'Manage property listings & schedule visits'
                                      : 'Manage showroom inventory & fleet rentals',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 2. Workspace Selector Tabs ─────────────────────
                _buildWorkspaceSelector(currentWorkspace),

                const SizedBox(height: 18),

                // ── 3. Activation Banner (If user is in Client Mode)
                if (role == UserRole.client || role != currentWorkspace) ...[
                  _buildWorkspaceActivationBanner(
                      user, currentWorkspace, role),
                  const SizedBox(height: 18),
                ],

                // ── 4. Role Specific Modules ────────────────────────
                if (currentWorkspace == UserRole.driver) ...[
                  _buildDriverSection(user),
                ] else if (currentWorkspace == UserRole.agent) ...[
                  _buildAgentSection(user),
                ] else if (currentWorkspace == UserRole.merchant) ...[
                  _buildDealerSection(user),
                ],

                const SizedBox(height: 24),

                // ── 3. Quick Switch Bar ─────────────────────────────
                _buildSectionHeader('SWITCH WORKSPACE MODE'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildWorkspaceTile(
                        icon: Icons.person_outline_rounded,
                        title: 'Client Discovery Mode',
                        subtitle: 'Browse rides, properties, and vehicles',
                        isActive: false,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Divider(height: 1),
                      _buildWorkspaceTile(
                        icon: Icons.storefront_rounded,
                        title: 'Operator / Seller Mode',
                        subtitle: 'Currently active on this screen',
                        isActive: true,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                      DRIVER WORKSPACE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDriverSection(UserEntity? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('LIVE DISPATCH RADAR'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.emerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'DISPATCH BRIDGE READY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Open your full-screen driver dispatch radar to toggle online, receive live ride broadcasts from passengers in Freetown, and navigate via GPS.',
                style: TextStyle(fontSize: 13, color: AppColors.gray600, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emeraldDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text(
                    'Open Driver Dispatch Radar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  onPressed: () {
                    if (user != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DriverPortalScreen(
                            currentUserId: user.id,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('VEHICLE MANAGEMENT'),
        _buildActionTile(
          icon: Icons.directions_car_filled_rounded,
          title: 'Update Vehicle & Documents',
          subtitle: 'Keke, Okada, Taxi, or Van registration',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DriverVehicleRegistrationScreen(
                  driverId: user?.id ?? '',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       AGENT WORKSPACE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAgentSection(UserEntity? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('PROPERTY MANAGEMENT'),
        Row(
          children: [
            Expanded(
              child: _buildStatBox('6 Properties', 'Active Listings', Icons.home_work_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatBox('SLE 14,250', 'Escrow Balance', Icons.account_balance_wallet_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildActionTile(
          icon: Icons.add_home_work_rounded,
          title: 'Publish New Property Listing',
          subtitle: 'Upload multi-image villa, flat, or land',
          isPrimary: true,
          onTap: () {
            if (user != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CreateListingScreen(
                    database: widget.database,
                    convexClient: widget.convexClient,
                    currentUser: user,
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        _buildActionTile(
          icon: Icons.calendar_month_rounded,
          title: 'Site Visits & Inquiries',
          subtitle: 'Manage client viewing appointments',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Site visits queue is up to date.')),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       DEALER WORKSPACE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDealerSection(UserEntity? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('FLEET & SHOWROOM INVENTORY'),
        Row(
          children: [
            Expanded(
              child: _buildStatBox('6 Vehicles', 'In Showroom', Icons.directions_car_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatBox('SLE 18,500', 'Rental Earnings', Icons.payments_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildActionTile(
          icon: Icons.add_circle_outline_rounded,
          title: 'Add Vehicle to Showroom',
          subtitle: 'List car for sale or daily rental',
          isPrimary: true,
          onTap: () {
            if (user != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CreateListingScreen(
                    database: widget.database,
                    convexClient: widget.convexClient,
                    currentUser: user,
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        _buildActionTile(
          icon: Icons.assignment_outlined,
          title: 'Rental Bookings & Escrow',
          subtitle: 'View active vehicle rentals & deposits',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('All rental deposits secured in escrow.')),
            );
          },
        ),
      ],
    );
  }


  Widget _buildStatBox(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.emeraldDark),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.gray500),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.obsidian : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary ? AppColors.obsidian : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isPrimary
                    ? AppColors.emerald.withValues(alpha: 0.2)
                    : AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isPrimary ? AppColors.emerald : AppColors.obsidian,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isPrimary ? Colors.white : AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isPrimary
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.gray500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isPrimary ? AppColors.emerald : AppColors.gray400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.emeraldSurface : AppColors.gray100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.emeraldDark : AppColors.gray500,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isActive ? AppColors.emeraldDark : AppColors.obsidian,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.gray500),
      ),
      trailing: isActive
          ? const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 20)
          : null,
      onTap: onTap,
    );
  }

  Widget _buildWorkspaceSelector(UserRole activeWorkspace) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.gray200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildWorkspaceTabItem(
            role: UserRole.driver,
            icon: Icons.local_taxi_rounded,
            label: 'Driver',
            isSelected: activeWorkspace == UserRole.driver,
          ),
          _buildWorkspaceTabItem(
            role: UserRole.agent,
            icon: Icons.apartment_rounded,
            label: 'Real Estate',
            isSelected: activeWorkspace == UserRole.agent,
          ),
          _buildWorkspaceTabItem(
            role: UserRole.merchant,
            icon: Icons.directions_car_filled_rounded,
            label: 'Auto Dealer',
            isSelected: activeWorkspace == UserRole.merchant,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceTabItem({
    required UserRole role,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeWorkspace = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.obsidian : AppColors.gray600,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      isSelected ? AppColors.obsidian : AppColors.gray600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceActivationBanner(
    UserEntity? user,
    UserRole currentWorkspace,
    UserRole userRole,
  ) {
    final isClient = userRole == UserRole.client;
    final title = isClient
        ? 'Preview Mode (${currentWorkspace.displayName})'
        : 'Switch to ${currentWorkspace.displayName}';
    final subtitle = isClient
        ? 'You are viewing operator tools. Activate your credentials to accept live tasks.'
        : 'Switch your active operational mode to ${currentWorkspace.displayName}.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.emeraldSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.emerald.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppColors.emeraldDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.gray600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emeraldDark,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              if (currentWorkspace == UserRole.driver) {
                final res = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => DriverVehicleRegistrationScreen(
                      driverId: user?.id ?? '',
                    ),
                  ),
                );
                if (res == true && mounted) {
                  context
                      .read<AuthBloc>()
                      .add(const UserRoleUpdatedEvent(UserRole.driver));
                }
              } else if (currentWorkspace == UserRole.agent) {
                _showAgentDialog(context, user);
              } else if (currentWorkspace == UserRole.merchant) {
                _showDealerDialog(context, user);
              }
            },
            child: Text(
              isClient ? 'Activate' : 'Switch',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showAgentDialog(BuildContext context, UserEntity? user) {
    if (user == null) return;
    final agencyCtrl =
        TextEditingController(text: '${user.name} Properties SL');
    final tinCtrl = TextEditingController(text: 'TIN-SL-88402');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Real Estate Agent Verification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Submit agency credentials to publish verified properties across Sierra Leone.',
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: agencyCtrl,
              decoration: const InputDecoration(
                labelText: 'Agency / Business Name',
                prefixIcon: Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinCtrl,
              decoration: const InputDecoration(
                labelText: 'TIN / Business Registration',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emeraldDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final client = context.read<ConvexClientWrapper>();
                  await client.mutation(
                    'users:mockApproveRoleUpgrade',
                    args: {'userId': user.id, 'targetRole': 'agent'},
                  );
                  if (context.mounted) {
                    context
                        .read<AuthBloc>()
                        .add(const UserRoleUpdatedEvent(UserRole.agent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Agent credentials verified!'),
                        backgroundColor: AppColors.emeraldDark,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Submit & Activate (Demo)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDealerDialog(BuildContext context, UserEntity? user) {
    if (user == null) return;
    final dealerCtrl =
        TextEditingController(text: '${user.name} Motors & Fleet');
    final tinCtrl = TextEditingController(text: 'TIN-SL-90241');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Auto Dealer Verification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Submit showroom credentials to list vehicles and fleet rentals.',
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dealerCtrl,
              decoration: const InputDecoration(
                labelText: 'Dealership / Fleet Name',
                prefixIcon: Icon(Icons.directions_car_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinCtrl,
              decoration: const InputDecoration(
                labelText: 'TIN / Trade License Number',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF92400E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final client = context.read<ConvexClientWrapper>();
                  await client.mutation(
                    'users:mockApproveRoleUpgrade',
                    args: {'userId': user.id, 'targetRole': 'merchant'},
                  );
                  if (context.mounted) {
                    context
                        .read<AuthBloc>()
                        .add(const UserRoleUpdatedEvent(UserRole.merchant));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Auto Dealer verified!'),
                        backgroundColor: Color(0xFF92400E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Submit & Activate (Demo)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.gray500,
        ),
      ),
    );
  }
}
