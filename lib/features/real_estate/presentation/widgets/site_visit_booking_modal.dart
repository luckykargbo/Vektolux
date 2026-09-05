// lib/features/real_estate/presentation/widgets/site_visit_booking_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Interactive Site Visit Inspection Calendar Modal
// Features anti-collision time slot selection and date-picker validation.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../bloc/real_estate_detail_bloc.dart';
import '../bloc/real_estate_detail_event.dart';
import '../bloc/real_estate_detail_state.dart';

class SiteVisitBookingModal extends StatefulWidget {
  final PropertyListingEntity listing;
  final String currentUserId;

  const SiteVisitBookingModal({
    super.key,
    required this.listing,
    required this.currentUserId,
  });

  static Future<void> show({
    required BuildContext context,
    required PropertyListingEntity listing,
    required String currentUserId,
    required RealEstateDetailBloc bloc,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: bloc,
        child: SiteVisitBookingModal(
          listing: listing,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  @override
  State<SiteVisitBookingModal> createState() => _SiteVisitBookingModalState();
}

class _SiteVisitBookingModalState extends State<SiteVisitBookingModal> {
  final TextEditingController _notesController = TextEditingController();

  // Standard business inspection slots
  static const List<String> _availableSlots = [
    '09:00 AM - 10:00 AM',
    '10:30 AM - 11:30 AM',
    '01:00 PM - 02:00 PM',
    '02:30 PM - 03:30 PM',
    '04:00 PM - 05:00 PM',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RealEstateDetailBloc, RealEstateDetailState>(
      listener: (context, state) {
        if (state.status == RealEstateDetailStatus.bookingSuccess) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.successMessage ?? 'Site visit scheduled successfully!',
                style: const TextStyle(color: AppColors.white),
              ),
              backgroundColor: AppColors.emerald,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (state.status == RealEstateDetailStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final selectedDate =
            state.selectedVisitDate ?? DateTime.now().add(const Duration(days: 1));

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Drag Handle ────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // ── 2. Modal Header ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: AppColors.emeraldDark,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Schedule Site Visit',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                          Text(
                            'Select an available inspection slot',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.gray500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.gray400),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              // ── 3. Scrollable Booking Body ────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Property mini banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.gray50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.home_work_outlined,
                              color: AppColors.obsidianSoft,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.listing.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.obsidian,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              'Complimentary',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Date Selector ─────────────────────────────
                      const Text(
                        '1. Choose Inspection Date',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Horizontal Day Picker (Next 14 Days)
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 14,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final date = DateTime.now().add(Duration(days: index + 1));
                            final isSelected = selectedDate.year == date.year &&
                                selectedDate.month == date.month &&
                                selectedDate.day == date.day;

                            return _buildDateCard(
                              date: date,
                              isSelected: isSelected,
                              onTap: () {
                                context
                                    .read<RealEstateDetailBloc>()
                                    .add(SelectVisitDateEvent(date));
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Time Slots Grid with Anti-Collision Check ─
                      Row(
                        children: [
                          const Text(
                            '2. Available Time Slots',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                          const Spacer(),
                          if (state.isLoadingBookedSlots)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.emerald,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Slots highlighted in red or disabled are already booked.',
                        style: TextStyle(fontSize: 12, color: AppColors.gray500),
                      ),
                      const SizedBox(height: 14),

                      // Slot chips wrap
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _availableSlots.map((slot) {
                          final isBooked = state.bookedSlotsForDate.contains(slot);
                          final isSelected = state.selectedTimeSlot == slot;

                          return _buildSlotChip(
                            slot: slot,
                            isBooked: isBooked,
                            isSelected: isSelected,
                            onTap: () {
                              if (!isBooked) {
                                context
                                    .read<RealEstateDetailBloc>()
                                    .add(SelectVisitTimeSlotEvent(slot));
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // ── Notes / Special Requests ──────────────────
                      const Text(
                        '3. Notes for Host / Agent (Optional)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'e.g., Interested in deed verification, parking inquiry...',
                          hintStyle: TextStyle(fontSize: 13, color: AppColors.gray400),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 4. Sticky Confirmation Action ─────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                child: SafeArea(
                  top: false,
                  child: VxButton(
                    label: state.selectedTimeSlot != null
                        ? 'Confirm Site Visit for ${state.selectedTimeSlot}'
                        : 'Select a Date & Time Slot',
                    isLoading: state.status == RealEstateDetailStatus.submitting,
                    onPressed: state.canConfirmSiteVisit
                        ? () {
                            context.read<RealEstateDetailBloc>().add(
                                  SubmitSiteVisitEvent(
                                    buyerId: widget.currentUserId,
                                    notes: _notesController.text.trim().isNotEmpty
                                        ? _notesController.text.trim()
                                        : null,
                                  ),
                                );
                          }
                        : null,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateCard({
    required DateTime date,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 68,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emerald : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekdays[date.weekday - 1],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.white : AppColors.gray500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.white : AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              months[date.month - 1],
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? AppColors.white.withValues(alpha: 0.8)
                    : AppColors.gray400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotChip({
    required String slot,
    required bool isBooked,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    Color bg;
    Color fg;
    BorderSide border;

    if (isBooked) {
      bg = AppColors.errorLight.withValues(alpha: 0.5);
      fg = AppColors.error;
      border = const BorderSide(color: AppColors.errorLight);
    } else if (isSelected) {
      bg = AppColors.emeraldSurface;
      fg = AppColors.emeraldDark;
      border = const BorderSide(color: AppColors.emerald, width: 2);
    } else {
      bg = AppColors.gray50;
      fg = AppColors.obsidian;
      border = const BorderSide(color: AppColors.border);
    }

    return GestureDetector(
      onTap: isBooked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBooked
                  ? Icons.block_rounded
                  : (isSelected
                      ? Icons.check_circle_rounded
                      : Icons.access_time_rounded),
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 8),
            Text(
              slot,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
                decoration: isBooked ? TextDecoration.lineThrough : null,
              ),
            ),
            if (isBooked) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'BOOKED',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
