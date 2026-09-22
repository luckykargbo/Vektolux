// lib/features/admin/presentation/views/admin_dashboard_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Master Admin Portal
// Full production management portal encompassing:
// 1. API Key Health, Management & Status Monitor
// 2. Agent & Merchant Code Configuration
// 3. Real-Time Financial & User Demographic Analytics
// 4. User Profile Auditing, Session Tracking & Device Logs
// 5. Seller/Dealer Phone Privacy & In-App Contact Relay
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';

import 'tabs/api_health_tab.dart';
import 'tabs/terminals_tab.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/user_audit_tab.dart';
import 'tabs/privacy_controls_tab.dart';

class AdminDashboardScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const AdminDashboardScreen({
    super.key,
    required this.convexClient,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        final isAdmin = user?.role == UserRole.admin;

        // Security Barrier: Only administrators can view this portal
        if (!isAdmin) {
          return Scaffold(
            backgroundColor: AppColors.gray50,
            appBar: AppBar(
              backgroundColor: AppColors.obsidian,
              foregroundColor: Colors.white,
              title: const Text('Access Denied'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.gpp_bad_outlined,
                      size: 64,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Administrator Access Required',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your current account does not have platform administrative privileges. Contact security operations if you believe this is an error.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.obsidianSoft,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.obsidian,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text(
                        'Return to App',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final adminUser = user!;
        final adminId = adminUser.id;
        final sessionToken = adminUser.sessionToken;

        return Scaffold(
          backgroundColor: AppColors.gray50,
          appBar: AppBar(
            backgroundColor: AppColors.obsidian,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Master Admin Portal',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PROD-LIVE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldLight,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Operator: ${adminUser.name} (${adminUser.email})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.obsidianSoft,
                  ),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.emerald,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.obsidianSoft,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.vpn_key_outlined, size: 18),
                  text: 'API Health',
                ),
                Tab(
                  icon: Icon(Icons.point_of_sale_outlined, size: 18),
                  text: 'Terminals',
                ),
                Tab(
                  icon: Icon(Icons.insights_outlined, size: 18),
                  text: 'Analytics',
                ),
                Tab(
                  icon: Icon(Icons.manage_accounts_outlined, size: 18),
                  text: 'User Audit',
                ),
                Tab(
                  icon: Icon(Icons.security_outlined, size: 18),
                  text: 'Privacy',
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              ApiHealthTab(
                convexClient: widget.convexClient,
                adminId: adminId,
                sessionToken: sessionToken,
              ),
              TerminalsTab(
                convexClient: widget.convexClient,
                adminId: adminId,
                sessionToken: sessionToken,
              ),
              AnalyticsTab(
                convexClient: widget.convexClient,
                adminId: adminId,
                sessionToken: sessionToken,
              ),
              UserAuditTab(
                convexClient: widget.convexClient,
                adminId: adminId,
                sessionToken: sessionToken,
              ),
              PrivacyControlsTab(
                convexClient: widget.convexClient,
                adminId: adminId,
                sessionToken: sessionToken,
              ),
            ],
          ),
        );
      },
    );
  }
}
