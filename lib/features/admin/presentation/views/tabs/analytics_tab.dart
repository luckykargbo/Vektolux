// lib/features/admin/presentation/views/tabs/analytics_tab.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Module 3: Real-Time Financial & Demographic Analytics
// Live transactional metrics, escrow velocity, role segmentation,
// gender demographics, and hourly transaction distribution. Zero mock data.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/theme/app_colors.dart';

class AnalyticsTab extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String adminId;
  final String? sessionToken;

  const AnalyticsTab({
    super.key,
    required this.convexClient,
    required this.adminId,
    this.sessionToken,
  });

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _financialData;
  Map<String, dynamic>? _demographicData;
  Map<String, dynamic>? _heatmapData;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final finFuture = widget.convexClient.query(
        'adminPortal:getFinancialSummary',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
        },
      );

      final demoFuture = widget.convexClient.query(
        'adminPortal:getUserDemographics',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
        },
      );

      final heatFuture = widget.convexClient.query(
        'adminPortal:getTransactionHeatmap',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
        },
      );

      final results = await Future.wait([finFuture, demoFuture, heatFuture]);

      if (mounted) {
        setState(() {
          _financialData = results[0].value != null && results[0].value is Map
              ? Map<String, dynamic>.from(results[0].value as Map)
              : null;
          _demographicData = results[1].value != null && results[1].value is Map
              ? Map<String, dynamic>.from(results[1].value as Map)
              : null;
          _heatmapData = results[2].value != null && results[2].value is Map
              ? Map<String, dynamic>.from(results[2].value as Map)
              : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.emerald));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.analytics_outlined,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Failed to load analytics: $_errorMessage'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchAnalytics,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final currencyFmt = NumberFormat('#,##0.00', 'en_US');
    final grossVolume = (_financialData?['grossVolume'] as num?)?.toDouble() ?? 0.0;
    final escrowLocked =
        (_financialData?['escrowLocked'] as num?)?.toDouble() ?? 0.0;
    final p2pCompleted =
        (_financialData?['p2pCompleted'] as num?)?.toDouble() ?? 0.0;
    final totalTx = (_financialData?['totalCount'] as num?)?.toInt() ?? 0;
    final completedTx = (_financialData?['completedCount'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: _fetchAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Header ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Financial Performance',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.obsidian,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.obsidian),
                onPressed: _fetchAnalytics,
                tooltip: 'Refresh Metrics',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ─── 4 Metric Cards Grid ───────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Gross Volume',
                  value: 'SLE ${currencyFmt.format(grossVolume)}',
                  icon: Icons.account_balance_wallet,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Escrow Locked',
                  value: 'SLE ${currencyFmt.format(escrowLocked)}',
                  icon: Icons.lock_clock,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'P2P Transfer Volume',
                  value: 'SLE ${currencyFmt.format(p2pCompleted)}',
                  icon: Icons.swap_horiz,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Settled Transactions',
                  value: '$completedTx of $totalTx',
                  icon: Icons.receipt_long,
                  color: AppColors.obsidianMedium,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── User Demographics & Roles ─────────────────────────────
          const Text(
            'User Segmentation & Roles',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 12),
          _buildRoleDistributionSection(),

          const SizedBox(height: 24),

          // ─── Gender Demographics ───────────────────────────────────
          const Text(
            'Gender Distribution',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 12),
          _buildGenderDistributionCard(),

          const SizedBox(height: 24),

          // ─── 24-Hour Transaction Heatmap ───────────────────────────
          const Text(
            'Transaction Activity by Hour (Last 7 Days)',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 12),
          _buildHourlyHeatmap(),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.obsidianLight.withOpacity(0.1),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.obsidianSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.obsidian,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleDistributionSection() {
    final roles = (_demographicData?['roleDistribution'] as Map<String, dynamic>?) ?? {};
    final totalUsers = (_demographicData?['totalUsers'] as num?)?.toInt() ?? 1;

    if (roles.isEmpty) {
      return const Text('No user data available', style: TextStyle(fontSize: 12));
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.obsidianLight.withOpacity(0.1), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: roles.entries.map((entry) {
            final count = (entry.value as num).toInt();
            final pct = totalUsers > 0 ? count / totalUsers : 0.0;
            final roleName = entry.key.replaceAll('_', ' ').toUpperCase();

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        roleName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidian,
                        ),
                      ),
                      Text(
                        '$count (${(pct * 100).toStringAsFixed(1)}%)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.obsidianSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: AppColors.gray50,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.emerald),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGenderDistributionCard() {
    final genders = (_demographicData?['genderDistribution'] as Map<String, dynamic>?) ?? {};
    final totalUsers = (_demographicData?['totalUsers'] as num?)?.toInt() ?? 1;

    final male = (genders['male'] as num?)?.toInt() ?? 0;
    final female = (genders['female'] as num?)?.toInt() ?? 0;
    final unspecified = (genders['unspecified'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.obsidianLight.withOpacity(0.1), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _buildGenderTile(
                label: 'Male',
                count: male,
                total: totalUsers,
                color: AppColors.info,
                icon: Icons.male,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGenderTile(
                label: 'Female',
                count: female,
                total: totalUsers,
                color: const Color(0xFFEC4899), // Pink
                icon: Icons.female,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGenderTile(
                label: 'Not Disclosed',
                count: unspecified,
                total: totalUsers,
                color: AppColors.obsidianSoft,
                icon: Icons.person_outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderTile({
    required String label,
    required int count,
    required int total,
    required Color color,
    required IconData icon,
  }) {
    final pct = total > 0 ? (count / total) * 100 : 0.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 0.8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.obsidian,
            ),
          ),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10, color: AppColors.obsidianSoft),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyHeatmap() {
    final hourly = (_heatmapData?['hourlyVolume'] as Map<String, dynamic>?) ?? {};

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.obsidianLight.withOpacity(0.1), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'UTC Hour Activity Breakdown',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.obsidianSoft,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (hour) {
                  final data = hourly[hour.toString()] as Map<String, dynamic>?;
                  final count = (data?['count'] as num?)?.toInt() ?? 0;
                  final heightFraction = (count / 10).clamp(0.08, 1.0);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 60 * heightFraction,
                            decoration: BoxDecoration(
                              color: count > 0
                                  ? AppColors.emerald
                                  : AppColors.obsidianLight.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hour % 4 == 0 ? '${hour}h' : '',
                            style: const TextStyle(
                              fontSize: 8,
                              color: AppColors.obsidianSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
