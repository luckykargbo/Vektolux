// lib/features/bookings/presentation/views/my_bookings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — My Bookings & Trips
// Tabbed browsing for Active vs Historical bookings powered directly by Convex Cloud.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/entities/booking_entity.dart';

class MyBookingsScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;

  const MyBookingsScreen({
    super.key,
    required this.convexClient,
    required this.currentUser,
  });

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<BookingEntity> _allBookings = [];
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchBookingsFromConvex();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookingsFromConvex() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await widget.convexClient.query(
        'bookings:getUserBookings',
        args: {'buyerId': widget.currentUser.id},
      );

      if (result.success && result.value is List) {
        final rawList = result.value as List;
        final list = rawList
            .map((item) => BookingEntity.fromJson(item as Map<String, dynamic>))
            .toList();

        if (mounted) {
          setState(() {
            _allBookings = list;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (_) {
      // Ignore or log error
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _cancelBooking(BookingEntity booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Cancel Booking?',
            style: TextStyle(
              color: isDark ? AppColors.white : AppColors.obsidian,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: Text(
            'Are you sure you want to cancel "${booking.listingTitle}"?',
            style: TextStyle(
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Keep Booking',
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final res = await widget.convexClient.mutation(
        'bookings:cancelBooking',
        args: {
          'bookingId': booking.id,
          'userId': widget.currentUser.id,
          'reason': 'Cancelled by customer',
        },
      );

      if (res.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking successfully cancelled'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _fetchBookingsFromConvex();
      } else {
        throw Exception(res.errorMessage ?? 'Failed to cancel booking');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeBookings = _allBookings
        .where((b) =>
            b.status != BookingStatus.completed &&
            b.status != BookingStatus.cancelled)
        .toList();

    final historicalBookings = _allBookings
        .where((b) =>
            b.status == BookingStatus.completed ||
            b.status == BookingStatus.cancelled)
        .toList();

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
            icon: _isLoading
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
            onPressed: _fetchBookingsFromConvex,
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
          _buildBookingList(
            list: activeBookings,
            emptyMessage: 'No upcoming stays or trips scheduled.',
          ),
          _buildBookingList(
            list: historicalBookings,
            emptyMessage: 'No past completed or cancelled bookings.',
          ),
        ],
      ),
    );
  }

  Widget _buildBookingList({
    required List<BookingEntity> list,
    required String emptyMessage,
  }) {
    if (_isLoading && list.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.emerald),
        ),
      );
    }

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
      onRefresh: _fetchBookingsFromConvex,
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
  }

  Widget _buildBookingCard(BookingEntity booking) {
    final isInspection = booking.bookingType == BookingType.propertyInspection ||
        booking.bookingType == BookingType.vehicleInspection;
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
                        : (booking.bookingType == BookingType.vehicleRental
                            ? Icons.directions_car_outlined
                            : Icons.bed_outlined),
                    size: 16,
                    color: AppColors.obsidian,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    booking.bookingType.displayName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                ],
              ),
              _buildStatusBadge(booking.status),
            ],
          ),
          const SizedBox(height: 10),

          // Listing Title
          Text(
            booking.listingTitle.isNotEmpty
                ? booking.listingTitle
                : 'Listing #${booking.listingId.length > 8 ? booking.listingId.substring(0, 8) : booking.listingId}',
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
              if (booking.status != BookingStatus.cancelled &&
                  booking.status != BookingStatus.completed) ...[
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

  Widget _buildStatusBadge(BookingStatus status) {
    Color bg;
    Color fg;
    String label = status.displayName;

    switch (status) {
      case BookingStatus.confirmed:
        bg = AppColors.emeraldSurface;
        fg = AppColors.emeraldDark;
        break;
      case BookingStatus.pendingPayment:
        bg = AppColors.amberSurface;
        fg = AppColors.amber;
        break;
      case BookingStatus.completed:
        bg = AppColors.gray100;
        fg = AppColors.gray700;
        break;
      case BookingStatus.cancelled:
        bg = AppColors.errorLight;
        fg = AppColors.error;
        break;
      case BookingStatus.inProgress:
        bg = AppColors.emeraldSurface;
        fg = AppColors.emerald;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
