// lib/features/bookings/presentation/views/my_bookings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — My Bookings & Trips
// Tabbed browsing for Active vs Historical bookings with Drift SQLite streams.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';

class MyBookingsScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;

  const MyBookingsScreen({
    super.key,
    required this.database,
    required this.convexClient,
    required this.currentUser,
  });

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSyncing = false;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _syncBookingsFromConvex();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _syncBookingsFromConvex() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final result = await widget.convexClient.query(
        'bookings:getUserBookings',
        args: {'buyerId': widget.currentUser.id},
      );

      if (result.success && result.value is List) {
        final rawList = result.value as List;
        final companions = rawList.map((item) {
          final m = item as Map<String, dynamic>;
          return CachedBookingsTableCompanion.insert(
            id: m['_id'] as String,
            listingId: m['listingId'] as String,
            listingTitle: drift.Value(m['listingTitle'] as String? ?? ''),
            buyerId: m['buyerId'] as String,
            vendorId: m['vendorId'] as String,
            bookingType: m['bookingType'] as String,
            startTime: (m['startTime'] as num).toInt(),
            endTime: (m['endTime'] as num).toInt(),
            totalAmount: (m['totalAmount'] as num).toDouble(),
            currency: drift.Value(m['currency'] as String? ?? 'SLE'),
            paymentStatus: m['paymentStatus'] as String,
            bookingStatus:
                drift.Value(m['status'] as String? ?? 'pending_payment'),
            cachedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }).toList();

        await widget.database.cachedBookingsDao.insertAll(companions);
      }
    } catch (_) {
      // Offline fallback
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _cancelBooking(CachedBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Text('Are you sure you want to cancel "${booking.listingTitle}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Booking'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // 1. Convex Mutation
      await widget.convexClient.mutation(
        'bookings:cancelBooking',
        args: {
          'bookingId': booking.id,
          'userId': widget.currentUser.id,
          'reason': 'Cancelled by customer',
        },
      );

      // 2. Update local Drift SQLite
      await widget.database.cachedBookingsDao.updateStatus(
        id: booking.id,
        bookingStatus: 'cancelled',
        paymentStatus: booking.paymentStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking successfully cancelled'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'My Bookings & Trips',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.emerald),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: AppColors.emerald),
            onPressed: _syncBookingsFromConvex,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelColor: AppColors.emerald,
          unselectedLabelColor: AppColors.gray400,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Active Bookings'),
            Tab(text: 'History / Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Active
          _buildBookingList(
            stream: widget.database.cachedBookingsDao
                .watchActiveUserBookings(widget.currentUser.id),
            emptyMessage: 'No upcoming stays or trips scheduled.',
          ),

          // Tab 2: Historical
          _buildBookingList(
            stream: widget.database.cachedBookingsDao
                .watchHistoricalUserBookings(widget.currentUser.id),
            emptyMessage: 'No past completed or cancelled bookings.',
          ),
        ],
      ),
    );
  }

  Widget _buildBookingList({
    required Stream<List<CachedBooking>> stream,
    required String emptyMessage,
  }) {
    return StreamBuilder<List<CachedBooking>>(
      stream: stream,
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];

        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.event_available_outlined,
                  size: 56,
                  color: AppColors.gray400,
                ),
                const SizedBox(height: 14),
                Text(
                  emptyMessage,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Explore Discovery Feed'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _syncBookingsFromConvex,
          color: AppColors.emerald,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final booking = list[index];
              return _buildBookingCard(booking);
            },
          ),
        );
      },
    );
  }

  Widget _buildBookingCard(CachedBooking booking) {
    final isInspection = booking.bookingType.contains('inspection');
    final startDate =
        DateTime.fromMillisecondsSinceEpoch(booking.startTime);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Type & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isInspection
                        ? Icons.visibility_outlined
                        : (booking.bookingType.contains('vehicle')
                            ? Icons.directions_car_outlined
                            : Icons.bed_outlined),
                    size: 16,
                    color: AppColors.obsidian,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    booking.bookingType.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                ],
              ),
              _buildStatusBadge(booking.bookingStatus),
            ],
          ),
          const SizedBox(height: 10),

          // Listing Title
          Text(
            booking.listingTitle.isNotEmpty
                ? booking.listingTitle
                : 'Listing #${booking.listingId.substring(0, 8)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),

          // Date & Time
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 14, color: AppColors.gray500),
              const SizedBox(width: 4),
              Text(
                DateFormat('EEE, MMM d, yyyy · h:mm a').format(startDate),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Financials & Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Amount',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    isInspection
                        ? 'FREE'
                        : 'SLE ${_currencyFormat.format(booking.totalAmount)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isInspection
                          ? AppColors.emeraldDark
                          : AppColors.obsidian,
                    ),
                  ),
                ],
              ),
              if (booking.bookingStatus != 'cancelled' &&
                  booking.bookingStatus != 'completed') ...[
                TextButton(
                  onPressed: () => _cancelBooking(booking),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'confirmed':
        bg = AppColors.emeraldSurface;
        fg = AppColors.emeraldDark;
        label = 'CONFIRMED';
        break;
      case 'pending_payment':
        bg = AppColors.amberSurface;
        fg = AppColors.amber;
        label = 'PENDING PAYMENT';
        break;
      case 'completed':
        bg = AppColors.gray100;
        fg = AppColors.gray700;
        label = 'COMPLETED';
        break;
      case 'cancelled':
        bg = AppColors.errorLight;
        fg = AppColors.error;
        label = 'CANCELLED';
        break;
      default:
        bg = AppColors.gray100;
        fg = AppColors.obsidian;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
