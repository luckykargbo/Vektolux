// lib/features/notifications/presentation/views/notifications_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — In-App Notification Center
// Displays real-time targeted and broadcast push notifications with
// read-state tracking, deep-link triggers, and pull-to-refresh.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';

class NotificationsScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final String? currentUserId;

  const NotificationsScreen({
    super.key,
    required this.convexClient,
    this.currentUserId,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all' | 'unread' | 'broadcast'

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final userId = widget.currentUserId ?? 'guest';
      final res = await widget.convexClient.query(
        'notifications:getUserNotifications',
        args: {
          'userId': userId,
          'limit': 50,
        },
      );

      if (res.success && res.value != null && mounted) {
        final list = List<Map<String, dynamic>>.from(
          (res.value as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[NotificationsScreen] Load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markNotificationRead(Map<String, dynamic> notif) async {
    if (notif['read'] == true) return;

    final notifId = notif['id'] as String;
    final userId = widget.currentUserId ?? 'guest';

    // Optimistically update UI
    setState(() {
      notif['read'] = true;
    });

    try {
      await widget.convexClient.mutation(
        'notifications:markAsRead',
        args: {
          'notificationId': notifId,
          'userId': userId,
        },
      );
    } catch (e) {
      debugPrint('[NotificationsScreen] Mark read error: $e');
    }
  }

  Future<void> _markAllRead() async {
    final userId = widget.currentUserId ?? 'guest';

    setState(() {
      for (final n in _notifications) {
        n['read'] = true;
      }
    });

    try {
      await widget.convexClient.mutation(
        'notifications:markAllAsRead',
        args: {'userId': userId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read.'),
            backgroundColor: AppColors.emeraldDark,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationsScreen] Mark all read error: $e');
    }
  }

  void _handleDeepLink(Map<String, dynamic> notif) {
    _markNotificationRead(notif);

    final screen = notif['deepLinkScreen'] as String? ?? 'notifications';

    switch (screen.toLowerCase()) {
      case 'home':
        Navigator.pop(context);
        MainNavigationShell.switchToTab(context, 0);
        break;
      case 'real_estate':
        Navigator.pop(context);
        MainNavigationShell.switchToTab(context, 2);
        break;
      case 'mobility':
        Navigator.pop(context);
        MainNavigationShell.switchToTab(context, 3);
        break;
      case 'profile':
        Navigator.pop(context);
        MainNavigationShell.switchToTab(context, 4);
        break;
      default:
        // Already on Notifications screen
        break;
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    final timeMs = timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0;
    if (timeMs == 0) return '';

    final date = DateTime.fromMillisecondsSinceEpoch(timeMs);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _notifications.where((n) {
      if (_selectedFilter == 'unread') return n['read'] != true;
      if (_selectedFilter == 'broadcast') return n['targetType'] == 'all_users';
      return true;
    }).toList();

    final unreadTotal = _notifications.where((n) => n['read'] != true).length;

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.obsidian,
              ),
            ),
            if (unreadTotal > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.emerald,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unreadTotal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        actions: [
          if (_notifications.isNotEmpty && unreadTotal > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Mark All Read',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.emeraldDark,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _buildFilterChip('All', 'all', _notifications.length),
                const SizedBox(width: 8),
                _buildFilterChip('Unread', 'unread', unreadTotal),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Announcements',
                  'broadcast',
                  _notifications.where((n) => n['targetType'] == 'all_users').length,
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Content List
          Expanded(
            child: RefreshIndicator(
              color: AppColors.emerald,
              onRefresh: _loadNotifications,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.emerald),
                    )
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final notif = filtered[index];
                            return _buildNotificationCard(notif);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.obsidian : AppColors.gray100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.gray600,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.emerald : AppColors.gray500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final isRead = notif['read'] == true;
    final isBroadcast = notif['targetType'] == 'all_users';
    final hasDeepLink = notif['deepLinkScreen'] != null &&
        (notif['deepLinkScreen'] as String).isNotEmpty &&
        notif['deepLinkScreen'] != 'notifications';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _handleDeepLink(notif),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFF0FDF4), // Emerald 50
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead ? AppColors.border : AppColors.emerald.withValues(alpha: 0.4),
            width: isRead ? 1.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isRead ? 0.02 : 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isBroadcast
                    ? AppColors.emeraldSurface
                    : AppColors.obsidian.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isBroadcast ? Icons.campaign_rounded : Icons.notifications_active_rounded,
                color: isBroadcast ? AppColors.emeraldDark : AppColors.obsidian,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isBroadcast) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.emerald,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'BROADCAST',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          notif['title'] ?? 'Notification',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notif['body'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: isRead ? AppColors.gray600 : AppColors.obsidian,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDate(notif['createdAt']),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.gray500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (hasDeepLink)
                        Row(
                          children: [
                            Text(
                              'Open ${_formatScreenName(notif['deepLinkScreen'])}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: AppColors.emeraldDark,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatScreenName(dynamic screen) {
    if (screen == null) return 'View';
    final s = screen.toString().replaceAll('_', ' ');
    return s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : 'View';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.gray100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 36,
                color: AppColors.gray400,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Notifications',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You are all caught up! Important escrow updates, ride notifications, and announcements will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.gray500, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
