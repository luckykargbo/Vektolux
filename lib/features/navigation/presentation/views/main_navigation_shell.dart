// lib/features/navigation/presentation/views/main_navigation_shell.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Super App Persistent Bottom Navigation Shell
// Coordinates 5 core verticals: Home Discovery, Rides (Hailing),
// Real Estate Marketplace, Auto Marketplace, and Account Profile.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../home/presentation/views/client_home_screen.dart';
import '../../../mobility/presentation/views/auto_marketplace_screen.dart';
import '../../../mobility/presentation/views/driver_portal_screen.dart';
import '../../../mobility/presentation/views/mobility_home_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';
import '../../../real_estate/presentation/views/real_estate_marketplace_screen.dart';

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

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
  }

  void setTab(int index) {
    if (index >= 0 && index < 5) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final database = context.read<AppDatabase>();
    final convexClient = context.read<ConvexClientWrapper>();

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final currentUserId = authState.user?.id ?? '';
        final isDriverMode = authState.user?.isDriverMode ?? false;

        // ── Strict View Isolation: Exclusively display Driver Portal when active_mode is 'driver' ──
        if (isDriverMode) {
          return DriverPortalScreen(
            currentUserId: currentUserId,
            initialLat: 8.484,
            initialLng: -13.229,
          );
        }

        final pages = [
          // 0: Home Super App Discovery
          ClientHomeScreen(
            database: database,
            convexClient: convexClient,
          ),

          // 1: Rides (Interactive Map, Keke/Okada/Taxi Hailing)
          MobilityHomeScreen(
            currentUserId: currentUserId,
            initialLat: 8.484,
            initialLng: -13.229,
          ),

          // 2: Real Estate Vertical Marketplace
          RealEstateMarketplaceScreen(
            database: database,
            convexClient: convexClient,
          ),

          // 3: Auto Market & Car Rentals Vertical
          AutoMarketplaceScreen(
            database: database,
            convexClient: convexClient,
          ),

          // 4: Account & Vendor Profile
          ProfileScreen(
            currentUserId: currentUserId,
          ),
        ];

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
          bottomNavigationBar: Container(
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
            child: SafeArea(
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(
                      index: 0,
                      label: 'Home',
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                    ),
                    _buildNavItem(
                      index: 1,
                      label: 'Rides',
                      icon: Icons.local_taxi_outlined,
                      activeIcon: Icons.local_taxi_rounded,
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
        );
      },
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => setTab(index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.emeraldDark : AppColors.gray500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
