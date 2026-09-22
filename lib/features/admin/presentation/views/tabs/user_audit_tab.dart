// lib/features/admin/presentation/views/tabs/user_audit_tab.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Module 4: User Profile Auditing, Session Tracking & Device Logs
// Comprehensive user inspection, live device telemetry, session history,
// and double-entry transaction timeline. Zero mock data.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/theme/app_colors.dart';

class UserAuditTab extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String adminId;
  final String? sessionToken;

  const UserAuditTab({
    super.key,
    required this.convexClient,
    required this.adminId,
    this.sessionToken,
  });

  @override
  State<UserAuditTab> createState() => _UserAuditTabState();
}

class _UserAuditTabState extends State<UserAuditTab> {
  bool _isLoading = true;
  String? _errorMessage;
  String _roleFilter = 'all';
  String _searchQuery = '';
  List<Map<String, dynamic>> _users = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.convexClient.query(
        'admin:getAllUsers',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
          if (_roleFilter != 'all') 'roleFilter': _roleFilter,
          if (_searchQuery.isNotEmpty) 'searchQuery': _searchQuery,
        },
      );

      if (mounted) {
        setState(() {
          _users = (res.value as List<dynamic>?)
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

  void _inspectUser(Map<String, dynamic> userSummary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _UserAuditDetailSheet(
        convexClient: widget.convexClient,
        adminId: widget.adminId,
        sessionToken: widget.sessionToken,
        targetUserId: userSummary['id'],
        onStatusChanged: _fetchUsers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Search Bar ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name, email, phone, business...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _fetchUsers();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onSubmitted: (val) {
              setState(() => _searchQuery = val.trim());
              _fetchUsers();
            },
          ),
        ),

        // ─── Role Filters ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildRoleChip('all', 'All'),
                const SizedBox(width: 8),
                _buildRoleChip('client', 'Clients'),
                const SizedBox(width: 8),
                _buildRoleChip('driver', 'Drivers'),
                const SizedBox(width: 8),
                _buildRoleChip('agent', 'Agents'),
                const SizedBox(width: 8),
                _buildRoleChip('merchant', 'Merchants'),
                const SizedBox(width: 8),
                _buildRoleChip('admin', 'Admins'),
              ],
            ),
          ),
        ),

        const Divider(height: 16),

        // ─── User List ───────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
              : _errorMessage != null
                  ? Center(child: Text('Error: $_errorMessage'))
                  : _users.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_search, size: 48, color: AppColors.obsidianSoft),
                              const SizedBox(height: 12),
                              const Text('No users match search criteria.', style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.emerald,
                          onRefresh: _fetchUsers,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: _users.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, index) => _buildUserCard(_users[index]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildRoleChip(String roleKey, String label) {
    final isSelected = _roleFilter == roleKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _roleFilter = roleKey);
          _fetchUsers();
        }
      },
      selectedColor: AppColors.obsidian,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected ? Colors.white : AppColors.obsidian,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
      backgroundColor: AppColors.gray50,
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = (user['activeRole'] ?? user['role'] ?? 'client').toString();
    final isVerified = user['isVerified'] == true;
    final isActive = user['isActive'] != false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.obsidianLight.withOpacity(0.1), width: 0.8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: AppColors.obsidianLight.withOpacity(0.1),
          backgroundImage: user['avatarUrl'] != null ? NetworkImage(user['avatarUrl']) : null,
          child: user['avatarUrl'] == null
              ? Text(
                  (user['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian),
                )
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user['name'] ?? 'Unnamed',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.obsidian),
              ),
            ),
            if (isVerified)
              const Icon(Icons.verified, size: 16, color: AppColors.emerald)
            else
              const Icon(Icons.shield_outlined, size: 16, color: AppColors.obsidianSoft),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${user['phone'] ?? ''} • ${user['email'] ?? ''}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.obsidianSoft),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianLight.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.obsidian),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.emeraldSurface : AppColors.errorLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'SUSPENDED',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: isActive ? AppColors.emeraldDark : AppColors.errorDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.obsidianSoft),
        onTap: () => _inspectUser(user),
      ),
    );
  }
}

// ─── Bottom Sheet: Extended User Audit View ─────────────────────────

class _UserAuditDetailSheet extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String adminId;
  final String? sessionToken;
  final String targetUserId;
  final VoidCallback onStatusChanged;

  const _UserAuditDetailSheet({
    required this.convexClient,
    required this.adminId,
    this.sessionToken,
    required this.targetUserId,
    required this.onStatusChanged,
  });

  @override
  State<_UserAuditDetailSheet> createState() => _UserAuditDetailSheetState();
}

class _UserAuditDetailSheetState extends State<_UserAuditDetailSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _auditData;

  @override
  void initState() {
    super.initState();
    _fetchAuditView();
  }

  Future<void> _fetchAuditView() async {
    try {
      final res = await widget.convexClient.query(
        'adminPortal:getAdminUserAuditView',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
          'targetUserId': widget.targetUserId,
        },
      );

      if (mounted) {
        setState(() {
          _auditData = res.value != null && res.value is Map
              ? Map<String, dynamic>.from(res.value as Map)
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

  Future<void> _toggleUserActive() async {
    final profile = _auditData?['profile'] as Map<String, dynamic>?;
    if (profile == null) return;
    final currentActive = profile['isActive'] != false;
    final nextActive = !currentActive;

    try {
      await widget.convexClient.mutation(
        'admin:toggleUserActiveStatus',
        args: {
          'adminId': widget.adminId,
          if (widget.sessionToken != null) 'sessionToken': widget.sessionToken,
          'userId': widget.targetUserId,
          'isActive': nextActive,
        },
      );
      widget.onStatusChanged();
      await _fetchAuditView();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 350,
        child: Center(child: CircularProgressIndicator(color: AppColors.emerald)),
      );
    }

    if (_errorMessage != null) {
      return SizedBox(
        height: 250,
        child: Center(child: Text('Error loading profile: $_errorMessage')),
      );
    }

    final profile = _auditData?['profile'] as Map<String, dynamic>? ?? {};
    final wallet = _auditData?['wallet'] as Map<String, dynamic>? ?? {};
    final sessions = (_auditData?['sessions'] as List<dynamic>?) ?? [];
    final transactions = (_auditData?['transactions'] as List<dynamic>?) ?? [];

    final currencyFmt = NumberFormat('#,##0.00', 'en_US');
    final availableBalance = (wallet['availableBalance'] as num?)?.toDouble() ?? 0.0;
    final escrowBalance = (wallet['escrowBalance'] as num?)?.toDouble() ?? 0.0;
    final isActive = profile['isActive'] != false;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          // Sheet Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'User Audit & Security Profile',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.obsidian,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Profile Overview Card
          Card(
            elevation: 0,
            color: AppColors.gray50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.obsidian,
                        backgroundImage:
                            profile['avatarUrl'] != null ? NetworkImage(profile['avatarUrl']) : null,
                        child: profile['avatarUrl'] == null
                            ? Text(
                                (profile['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile['name'] ?? 'Unnamed',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.obsidian),
                            ),
                            Text(
                              '${profile['phone'] ?? ''} • ${profile['email'] ?? ''}',
                              style: const TextStyle(fontSize: 12, color: AppColors.obsidianSoft),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      _buildMiniInfo('ROLE', (profile['role'] ?? '').toString().toUpperCase()),
                      _buildMiniInfo('GENDER', (profile['gender'] ?? 'unspecified').toString().toUpperCase()),
                      _buildMiniInfo('REGION', (profile['region'] ?? 'Unknown').toString()),
                      _buildMiniInfo('STATUS', isActive ? 'ACTIVE' : 'SUSPENDED'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Wallet Balances Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AVAILABLE BALANCE',
                        style: TextStyle(fontSize: 10, color: AppColors.obsidianSoft, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SLE ${currencyFmt.format(availableBalance)}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LOCKED IN ESCROW',
                        style: TextStyle(fontSize: 10, color: AppColors.obsidianSoft, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SLE ${currencyFmt.format(escrowBalance)}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Status Action Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _toggleUserActive,
              icon: Icon(isActive ? Icons.block : Icons.check_circle_outline, size: 16),
              label: Text(isActive ? 'Suspend User Account' : 'Reactivate User Account'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isActive ? AppColors.errorDark : AppColors.emeraldDark,
                side: BorderSide(color: isActive ? AppColors.error : AppColors.emerald),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Device & Session Logs Section
          Row(
            children: [
              const Icon(Icons.devices, size: 18, color: AppColors.obsidian),
              const SizedBox(width: 8),
              const Text(
                'Device & Active Sessions',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.obsidian),
              ),
              const Spacer(),
              Text('${sessions.length} recorded', style: const TextStyle(fontSize: 11, color: AppColors.obsidianSoft)),
            ],
          ),
          const SizedBox(height: 8),

          if (sessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.gray50, borderRadius: BorderRadius.circular(8)),
              child: const Text('No active device sessions registered.', style: TextStyle(fontSize: 12, color: AppColors.obsidianSoft)),
            )
          else
            ...sessions.map((s) => _buildSessionTile(Map<String, dynamic>.from(s as Map))),

          const SizedBox(height: 20),

          // Recent Transactions Section
          Row(
            children: [
              const Icon(Icons.receipt_long, size: 18, color: AppColors.obsidian),
              const SizedBox(width: 8),
              const Text(
                'Recent Transactions',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.obsidian),
              ),
              const Spacer(),
              Text('${transactions.length} items', style: const TextStyle(fontSize: 11, color: AppColors.obsidianSoft)),
            ],
          ),
          const SizedBox(height: 8),

          if (transactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.gray50, borderRadius: BorderRadius.circular(8)),
              child: const Text('No transactions found for this user.', style: TextStyle(fontSize: 12, color: AppColors.obsidianSoft)),
            )
          else
            ...transactions.map((tx) => _buildTxTile(Map<String, dynamic>.from(tx as Map), currencyFmt)),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.obsidianSoft)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
        ],
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> s) {
    final isActive = s['isActive'] == true;
    final timeStr = s['loginAt'] != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(s['loginAt'] as int))
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.obsidianLight.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            s['deviceModel'].toString().toLowerCase().contains('iphone') ? Icons.phone_iphone : Icons.smartphone,
            size: 20,
            color: isActive ? AppColors.emerald : AppColors.obsidianSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s['deviceModel'] ?? 'Unknown'} • ${s['osVersion'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.obsidian),
                ),
                Text(
                  'Logged in: $timeStr (App v${s['appVersion'] ?? '1.0'})',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.obsidianSoft),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isActive ? AppColors.emeraldSurface : AppColors.gray50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isActive ? 'ONLINE' : 'LOGGED OUT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isActive ? AppColors.emeraldDark : AppColors.obsidianSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTxTile(Map<String, dynamic> tx, NumberFormat fmt) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final status = (tx['status'] as String? ?? 'completed').toLowerCase();
    final isSuccess = status == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.obsidianLight.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.pending,
            size: 16,
            color: isSuccess ? AppColors.emerald : AppColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (tx['type'] as String? ?? 'TRANSACTION').replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, color: AppColors.obsidian),
                ),
                if (tx['description'] != null)
                  Text(
                    tx['description'],
                    style: const TextStyle(fontSize: 10.5, color: AppColors.obsidianSoft),
                  ),
              ],
            ),
          ),
          Text(
            'SLE ${fmt.format(amount)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.obsidian),
          ),
        ],
      ),
    );
  }
}
