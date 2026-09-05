// lib/features/real_estate/presentation/widgets/hourly_booking_panel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Hourly Guest House Instant Booking Panel
// Dynamic duration slider (2h, 4h, overnight), live price calculation,
// and payment gateway trigger (Flutterwave / Paystack).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../bloc/real_estate_detail_bloc.dart';
import '../bloc/real_estate_detail_event.dart';
import '../bloc/real_estate_detail_state.dart';

class HourlyBookingPanel extends StatefulWidget {
  final PropertyListingEntity listing;
  final String currentUserId;
  final String userEmail;
  final String? userPhone;
  final String? userName;

  const HourlyBookingPanel({
    super.key,
    required this.listing,
    required this.currentUserId,
    required this.userEmail,
    this.userPhone,
    this.userName,
  });

  @override
  State<HourlyBookingPanel> createState() => _HourlyBookingPanelState();
}

class _HourlyBookingPanelState extends State<HourlyBookingPanel> {
  String _selectedPaymentMethod = 'mobile_money'; // 'mobile_money' or 'card'
  String _selectedGateway = 'flutterwave'; // 'flutterwave' or 'paystack'

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RealEstateDetailBloc, RealEstateDetailState>(
      builder: (context, state) {
        final hourlyRate = widget.listing.effectiveHourlyRate;
        final duration = state.hourlyDuration;
        final isOvernight = state.isOvernight;
        final total = state.calculatedTotal;
        final fee = state.hourlyPlatformFee;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidian.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header & Hourly Base Rate ─────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            color: AppColors.amber,
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Instant Guest House Booking',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Zero host waiting time • Instant lock',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.gray500,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${widget.listing.currency} ${hourlyRate.toStringAsFixed(0)}',
                        style: AppTypography.priceDisplay.copyWith(
                          fontSize: 20,
                        ),
                      ),
                      const Text(
                        '/ hour base',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.gray500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── Quick Duration Preset Chips ───────────────────────
              const Text(
                'Select Stay Duration',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildDurationChip(
                    context: context,
                    label: '2 Hours',
                    hours: 2,
                    isOvernight: false,
                    isSelected: !isOvernight && duration == 2,
                  ),
                  const SizedBox(width: 8),
                  _buildDurationChip(
                    context: context,
                    label: '4 Hours',
                    hours: 4,
                    isOvernight: false,
                    isSelected: !isOvernight && duration == 4,
                  ),
                  const SizedBox(width: 8),
                  _buildDurationChip(
                    context: context,
                    label: '8 Hours',
                    hours: 8,
                    isOvernight: false,
                    isSelected: !isOvernight && duration == 8,
                  ),
                  const SizedBox(width: 8),
                  _buildDurationChip(
                    context: context,
                    label: 'Overnight 🌙',
                    hours: 12,
                    isOvernight: true,
                    isSelected: isOvernight,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Interactive Duration Slider ───────────────────────
              if (!isOvernight) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Custom Duration: $duration Hours',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                    ),
                    Text(
                      'Max 12h',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.gray400,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.emerald,
                    inactiveTrackColor: AppColors.gray200,
                    thumbColor: AppColors.emerald,
                    overlayColor: AppColors.emerald.withValues(alpha: 0.15),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                    ),
                  ),
                  child: Slider(
                    value: duration.toDouble(),
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: '$duration hrs',
                    onChanged: (val) {
                      context.read<RealEstateDetailBloc>().add(
                            UpdateHourlyDurationEvent(
                              durationHours: val.round(),
                              isOvernight: false,
                            ),
                          );
                    },
                  ),
                ),
              ],

              // ── Dynamic Pricing Breakdown ─────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isOvernight
                              ? 'Overnight bundle (12 hrs @ 15% discount)'
                              : '${widget.listing.currency} ${hourlyRate.toStringAsFixed(0)} × $duration hours',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.gray600,
                          ),
                        ),
                        Text(
                          '${widget.listing.currency} ${(total - fee).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Vektolux platform fee (10%)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.gray600,
                          ),
                        ),
                        Text(
                          '${widget.listing.currency} ${fee.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Payable',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.obsidian,
                          ),
                        ),
                        Text(
                          '${widget.listing.currency} ${total.toStringAsFixed(0)}',
                          style: AppTypography.priceDisplay.copyWith(
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Payment Gateway Selection ─────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentMethodTile(
                      label: 'Mobile Money',
                      subtitle: 'Orange / Africell',
                      icon: Icons.phone_android_rounded,
                      isSelected: _selectedPaymentMethod == 'mobile_money',
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'mobile_money';
                          _selectedGateway = 'flutterwave';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPaymentMethodTile(
                      label: 'Card Checkout',
                      subtitle: 'Visa / Mastercard',
                      icon: Icons.credit_card_rounded,
                      isSelected: _selectedPaymentMethod == 'card',
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'card';
                          _selectedGateway = 'paystack';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Action CTA Button ─────────────────────────────────
              VxButton(
                label: 'Instant Book & Pay (${widget.listing.currency} ${total.toStringAsFixed(0)})',
                icon: Icons.flash_on_rounded,
                isLoading: state.status == RealEstateDetailStatus.submitting,
                onPressed: () {
                  context.read<RealEstateDetailBloc>().add(
                        SubmitInstantHourlyBookingEvent(
                          buyerId: widget.currentUserId,
                          customerEmail: widget.userEmail,
                          customerPhone: widget.userPhone,
                          customerName: widget.userName,
                          paymentMethod: _selectedPaymentMethod,
                          gatewayProvider: _selectedGateway,
                        ),
                      );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDurationChip({
    required BuildContext context,
    required String label,
    required int hours,
    required bool isOvernight,
    required bool isSelected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          context.read<RealEstateDetailBloc>().add(
                UpdateHourlyDurationEvent(
                  durationHours: hours,
                  isOvernight: isOvernight,
                ),
              );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.emeraldSurface : AppColors.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.emerald : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emeraldSurface : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.emeraldDark : AppColors.gray500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.gray500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
