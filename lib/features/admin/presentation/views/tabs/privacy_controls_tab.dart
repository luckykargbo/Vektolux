// lib/features/admin/presentation/views/tabs/privacy_controls_tab.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Module 5: Seller/Dealer Phone Privacy & In-App Relay
// Enforces database-level phone masking, prevents data leaks on vehicle &
// property discovery, and manages buyer-to-seller relay inquiries. Zero mock data.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/theme/app_colors.dart';

class PrivacyControlsTab extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String adminId;
  final String? sessionToken;

  const PrivacyControlsTab({
    super.key,
    required this.convexClient,
    required this.adminId,
    this.sessionToken,
  });

  @override
  State<PrivacyControlsTab> createState() => _PrivacyControlsTabState();
}

class _PrivacyControlsTabState extends State<PrivacyControlsTab> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _contactRequests = [];

  @override
  void initState() {
    super.initState();
    _fetchPrivacyData();
  }

  Future<void> _fetchPrivacyData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.convexClient.query(
        'adminPortal:getSellerContactRequests',
        args: {
          'sellerId': widget.adminId,
        },
      );

      if (mounted) {
        setState(() {
          _contactRequests = (res.value as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
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

  Future<void> _respondToRequest(String reqId, String action) async {
    try {
      final res = await widget.convexClient.mutation(
        'adminPortal:respondToContactRequest',
        args: {
          'sellerId': widget.adminId,
          'requestId': reqId,
          'action': action,
        },
      );

      if (mounted) {
        final resData = res.value != null && res.value is Map
            ? Map<String, dynamic>.from(res.value as Map)
            : {};
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resData['message'] ?? 'Responded to contact request.'),
            backgroundColor: action == 'accepted' ? AppColors.success : AppColors.obsidianSoft,
          ),
        );
        _fetchPrivacyData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: _fetchPrivacyData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Privacy Guard Status Banner ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.emeraldSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.emeraldLight, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.emerald, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Database-Level Phone Privacy Active',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Direct seller phone numbers are permanently omitted from all public catalog responses (getVehicleById, listProperties, and getSocialFeed).',
                        style: TextStyle(fontSize: 11.5, color: AppColors.obsidianMedium),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Privacy Rules Grid ──────────────────────────────────────
          const Text(
            'Enforcement Architecture',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 10),

          _buildRuleCard(
            title: 'Vehicle Listings (getVehicleById)',
            description:
                'owner.phone is stripped at the database query handler. Returns hasVerifiedPhone: boolean to prove verified contact without leaking raw digits.',
            status: 'PROTECTED',
            icon: Icons.directions_car,
          ),
          const SizedBox(height: 8),

          _buildRuleCard(
            title: 'Real Estate Catalog (listProperties)',
            description:
                'privateContactPhone is destructured and omitted from public listings before serialization.',
            status: 'PROTECTED',
            icon: Icons.home_work_outlined,
          ),
          const SizedBox(height: 8),

          _buildRuleCard(
            title: 'Social Activity Feed (getSocialFeed)',
            description:
                'All vehicle and property cards strip privateContactPhone and contactPhone fields prior to feed delivery.',
            status: 'PROTECTED',
            icon: Icons.dynamic_feed,
          ),
          const SizedBox(height: 8),

          _buildRuleCard(
            title: 'In-App Contact Relay (contact_requests)',
            description:
                'Buyers submit inquiries through secure internal messaging. Seller phone numbers are only disclosed if the seller explicitly accepts the contact request.',
            status: 'RELAY ACTIVE',
            icon: Icons.mark_chat_read_outlined,
          ),

          const SizedBox(height: 24),

          // ─── Contact Request Relay Queue ─────────────────────────────
          Row(
            children: [
              const Icon(Icons.inbox, size: 18, color: AppColors.obsidian),
              const SizedBox(width: 8),
              const Text(
                'In-App Contact Inquiries',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.obsidian,
                ),
              ),
              const Spacer(),
              Text(
                '${_contactRequests.length} inquiries',
                style: const TextStyle(fontSize: 11, color: AppColors.obsidianSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.emerald),
            ))
          else if (_errorMessage != null)
            Center(child: Text('Error loading requests: $_errorMessage'))
          else if (_contactRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.obsidianLight.withOpacity(0.1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.obsidianSoft, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No pending contact requests. Inquiries sent by buyers for your listings will appear here.',
                      style: TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._contactRequests.map((req) => _buildContactRequestTile(req)),
        ],
      ),
    );
  }

  Widget _buildRuleCard({
    required String title,
    required String description,
    required String status,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.obsidianLight.withOpacity(0.1), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.obsidianLight.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.obsidian),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.obsidian),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.emeraldDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 11, color: AppColors.obsidianSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactRequestTile(Map<String, dynamic> req) {
    final status = req['status'] as String? ?? 'pending';
    final isPending = status == 'pending';
    final isAccepted = status == 'accepted';

    final Color badgeColor = isAccepted
        ? AppColors.emerald
        : (isPending ? AppColors.amberDark : AppColors.obsidianSoft);

    final timeStr = req['createdAt'] != null
        ? DateFormat('dd MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(req['createdAt'] as int))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.obsidianLight.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.obsidian,
                child: Text(
                  (req['buyerName'] as String? ?? 'B').substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req['buyerName'] ?? 'Buyer',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.obsidian),
                    ),
                    Text(
                      '${(req['listingType'] ?? '').toString().toUpperCase()} Listing • $timeStr',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.obsidianSoft),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.gray50, borderRadius: BorderRadius.circular(6)),
            child: Text(
              '"${req['message'] ?? ''}"',
              style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.obsidianMedium),
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _respondToRequest(req['id'], 'declined'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorDark,
                    side: const BorderSide(color: AppColors.error, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Decline', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _respondToRequest(req['id'], 'accepted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Accept & Share Phone', style: TextStyle(fontSize: 11, color: Colors.white)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
