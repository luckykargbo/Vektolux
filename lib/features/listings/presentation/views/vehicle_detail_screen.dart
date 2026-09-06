// lib/features/listings/presentation/views/vehicle_detail_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Detail Screen
// Hero carousel, full technical specs, dealer credentials, and
// interactive physical inspection / test drive scheduling with escrow.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../bookings/presentation/views/checkout_screen.dart';
import '../../../mobility/domain/entities/mobility_vehicle_entity.dart';
import '../../../mobility/presentation/widgets/in_app_chat_modal.dart';

class VehicleDetailScreen extends StatefulWidget {
  final String id;
  final String make;
  final String model;
  final int year;
  final String vehicleType; // bike, taxi, delivery_van, truck, etc.
  final String listingIntent; // sale, rental, ride_hailing
  final double? salePrice;
  final double? pricePerDay;
  final double? pricePerKm;
  final List<String> imageUrls;
  final String? ownerId;
  final String? ownerName;
  final String? ownerPhone;
  final String? color;
  final String? licensePlate;
  final String? transmission;
  final String? fuelType;
  final String? mileage;
  final String? location;

  const VehicleDetailScreen({
    super.key,
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    required this.vehicleType,
    required this.listingIntent,
    this.salePrice,
    this.pricePerDay,
    this.pricePerKm,
    this.imageUrls = const [],
    this.ownerId,
    this.ownerName,
    this.ownerPhone,
    this.color,
    this.licensePlate,
    this.transmission,
    this.fuelType,
    this.mileage,
    this.location,
  });

  /// Factory constructor for CachedVehicleListing from Drift SQLite
  factory VehicleDetailScreen.fromCached(CachedVehicleListing cached) {
    return VehicleDetailScreen(
      id: cached.id,
      make: cached.make,
      model: cached.model,
      year: cached.year,
      vehicleType: cached.vehicleType,
      listingIntent: cached.listingIntent,
      salePrice: cached.salePrice,
      pricePerDay: cached.pricePerDay,
      pricePerKm: cached.pricePerKm,
      imageUrls: cached.primaryImageUrl != null ? [cached.primaryImageUrl!] : [],
      ownerId: cached.ownerId,
    );
  }

  /// Factory constructor for VehicleListingEntity
  factory VehicleDetailScreen.fromEntity(VehicleListingEntity entity) {
    return VehicleDetailScreen(
      id: entity.id,
      make: entity.make,
      model: entity.model,
      year: entity.year,
      vehicleType: entity.vehicleType.backendKey,
      listingIntent: entity.listingIntent,
      salePrice: entity.salePrice,
      pricePerDay: entity.pricePerDay,
      pricePerKm: entity.pricePerKm,
      imageUrls: entity.imageUrls,
      ownerId: entity.ownerId,
      ownerName: entity.ownerName,
      ownerPhone: entity.ownerPhone,
      color: entity.color,
      licensePlate: entity.licensePlate,
    );
  }

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  final PageController _pageController = PageController();
  int _activeImageIndex = 0;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _title => '${widget.make} ${widget.model} (${widget.year})';

  String get _priceFormatted {
    if (widget.listingIntent == 'sale' && widget.salePrice != null) {
      return 'SLE ${_currencyFormat.format(widget.salePrice)}';
    }
    if (widget.listingIntent == 'rental' && widget.pricePerDay != null) {
      return 'SLE ${_currencyFormat.format(widget.pricePerDay)} / day';
    }
    if (widget.listingIntent == 'ride_hailing' && widget.pricePerKm != null) {
      return 'SLE ${_currencyFormat.format(widget.pricePerKm)} / km';
    }
    if (widget.salePrice != null) {
      return 'SLE ${_currencyFormat.format(widget.salePrice)}';
    }
    return 'Contact for Price';
  }

  String get _badgeText => switch (widget.listingIntent) {
        'sale' => 'FOR SALE',
        'rental' => 'DAILY RENTAL',
        'ride_hailing' => 'RIDE HAILING',
        _ => widget.listingIntent.toUpperCase(),
      };

  Color get _badgeColor => switch (widget.listingIntent) {
        'sale' => AppColors.emerald,
        'rental' => const Color(0xFF06B6D4), // Cyan
        _ => const Color(0xFF6366F1), // Indigo
      };

  void _openScheduleInspectionModal(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to schedule a vehicle inspection or test drive.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    final notesController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final formattedDate = DateFormat('EEE, MMM d, yyyy').format(selectedDate);
            final formattedTime = selectedTime.format(ctx);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.car_crash_outlined,
                          color: AppColors.emeraldDark,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Physical Inspection & Test Drive',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            Text(
                              'Escrow-guaranteed 120-point mechanical check',
                              style: TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Vehicle Target
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_rounded, color: AppColors.obsidian, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                        ),
                        Text(
                          _priceFormatted,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date Picker Trigger
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    leading: const Icon(Icons.calendar_month_outlined, color: AppColors.emerald),
                    title: const Text('Inspection Date', style: TextStyle(fontSize: 12, color: AppColors.gray500)),
                    subtitle: Text(formattedDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.gray400),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  // Time Picker Trigger
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    leading: const Icon(Icons.access_time_rounded, color: AppColors.emerald),
                    title: const Text('Inspection Time', style: TextStyle(fontSize: 12, color: AppColors.gray500)),
                    subtitle: Text(formattedTime, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.gray400),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setModalState(() => selectedTime = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Location note
                  TextFormField(
                    controller: notesController,
                    style: const TextStyle(color: AppColors.obsidian, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Special Inspection Requests / Notes',
                      hintText: 'e.g. Bring mechanic to Lumley showroom',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              final convexClient = context.read<ConvexClientWrapper>();

                              final startDateTime = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                selectedTime.hour,
                                selectedTime.minute,
                              );
                              final endDateTime = startDateTime.add(const Duration(hours: 1));

                              try {
                                await convexClient.mutation(
                                  'bookings:createBooking',
                                  args: {
                                    'buyerId': user.id,
                                    'vendorId': widget.ownerId ?? 'vendor_system',
                                    'listingId': widget.id,
                                    'listingType': 'vehicle',
                                    'listingTitle': _title,
                                    'bookingType': 'vehicle_inspection',
                                    'startTime': startDateTime.millisecondsSinceEpoch,
                                    'endTime': endDateTime.millisecondsSinceEpoch,
                                    'subtotal': 0,
                                    'notes': notesController.text.trim().isNotEmpty
                                        ? notesController.text.trim()
                                        : 'Inspection scheduled for $_title',
                                  },
                                );

                                if (modalCtx.mounted) {
                                  Navigator.of(modalCtx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Inspection confirmed for $formattedDate at $formattedTime!'),
                                      backgroundColor: AppColors.emerald,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSubmitting = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to schedule inspection: $e'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2),
                            )
                          : const Text('Confirm Physical Inspection (Free)'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleRentalCheckout(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to rent this vehicle.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dailyRate = widget.pricePerDay ?? 350.0;
    const days = 3;
    final subtotal = dailyRate * days;
    final serviceFee = (subtotal * 0.05).roundToDouble();
    final total = subtotal + serviceFee;
    final now = DateTime.now();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          database: context.read<AppDatabase>(),
          convexClient: context.read<ConvexClientWrapper>(),
          currentUser: user,
          listingId: widget.id,
          listingType: 'vehicle',
          listingTitle: _title,
          listingSubtitle: '$days Days Daily Rental in Sierra Leone',
          primaryImageUrl: widget.imageUrls.isNotEmpty ? widget.imageUrls.first : null,
          vendorId: widget.ownerId ?? 'fleet_operator',
          bookingType: 'vehicle_rental',
          startTime: now.millisecondsSinceEpoch,
          endTime: now.add(const Duration(days: days)).millisecondsSinceEpoch,
          days: days,
          subtotal: subtotal,
          serviceFee: serviceFee,
          totalAmount: total,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls;

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
        title: Text(
          _title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.white),
            tooltip: 'Share listing',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Listing link copied to clipboard.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Hero Image Carousel ──────────────────────────────
            Stack(
              children: [
                SizedBox(
                  height: 250,
                  width: double.infinity,
                  child: images.isNotEmpty
                      ? PageView.builder(
                          controller: _pageController,
                          itemCount: images.length,
                          onPageChanged: (idx) => setState(() => _activeImageIndex = idx),
                          itemBuilder: (ctx, idx) {
                            return Image.network(
                              images[idx],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackHero(),
                            );
                          },
                        )
                      : _buildFallbackHero(),
                ),
                // Badge: Intent
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _badgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _badgeText,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                // Price Tag
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _priceFormatted,
                      style: const TextStyle(
                        color: AppColors.emerald,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                // Dot Indicators
                if (images.length > 1)
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: Row(
                      children: List.generate(images.length, (idx) {
                        final isSel = idx == _activeImageIndex;
                        return Container(
                          margin: const EdgeInsets.only(right: 4),
                          width: isSel ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.white : AppColors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),

            // ── 2. Header & Main Info ───────────────────────────────
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 15, color: AppColors.gray500),
                                const SizedBox(width: 4),
                                Text(
                                  widget.location ?? 'Freetown, Sierra Leone',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 14, color: AppColors.emeraldDark),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // ── 3. Technical Specs Grid ───────────────────────
                  const Text(
                    'Vehicle Specifications',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 12),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.6,
                    children: [
                      _buildSpecTile(Icons.calendar_today_rounded, 'Year', '${widget.year}'),
                      _buildSpecTile(Icons.directions_car_outlined, 'Type', widget.vehicleType.toUpperCase()),
                      _buildSpecTile(Icons.settings_outlined, 'Transmission', widget.transmission ?? 'Automatic'),
                      _buildSpecTile(Icons.local_gas_station_outlined, 'Fuel', widget.fuelType ?? 'Petrol'),
                      _buildSpecTile(Icons.speed_outlined, 'Mileage', widget.mileage ?? '42,000 km'),
                      _buildSpecTile(Icons.color_lens_outlined, 'Color', widget.color ?? 'Silver metallic'),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── 4. Key Equipment & Features ───────────────────
                  const Text(
                    'Key Features & Equipment',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FeatureChip('A/C Climate Control'),
                      _FeatureChip('Bluetooth Audio'),
                      _FeatureChip('Reverse Camera'),
                      _FeatureChip('GPS Tracking'),
                      _FeatureChip('Anti-Lock Brakes (ABS)'),
                      _FeatureChip('Escrow Guarantee'),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 18),

                  // ── 5. Dealer / Host Card ─────────────────────────
                  const Text(
                    'Seller / Fleet Operator',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.obsidian,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.storefront_rounded, color: AppColors.emerald, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.ownerName ?? 'Sierra Star Motors Ltd',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Licensed Merchant • Freetown Showroom',
                                style: TextStyle(fontSize: 11, color: AppColors.gray500),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.emeraldDark),
                          tooltip: 'Chat with Seller',
                          onPressed: () {
                            InAppChatModal.show(
                              context,
                              recipientName: widget.ownerName ?? 'Sierra Star Motors',
                              recipientRole: 'Vehicle Dealer',
                              vehicleTitle: _title,
                              vehiclePrice: _priceFormatted,
                              recipientPhone: widget.ownerPhone,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── 6. Escrow Guarantee Notice ────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_rounded, color: AppColors.emeraldDark, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'VEKTOLUX ESCROW GUARANTEE: Payments are locked in smart contract escrow until you conduct a physical inspection or completed rental handover.',
                            style: TextStyle(
                              color: AppColors.emeraldDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 100), // Padding for sticky bottom CTA
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).padding.bottom + 14,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Price', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                Text(
                  _priceFormatted,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: widget.listingIntent == 'rental'
                  ? VxButton(
                      label: 'Rent Now',
                      icon: Icons.key_rounded,
                      onPressed: () => _handleRentalCheckout(context),
                    )
                  : VxButton(
                      label: 'Schedule Inspection',
                      icon: Icons.calendar_today_rounded,
                      onPressed: () => _openScheduleInspectionModal(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackHero() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(
          Icons.directions_car_rounded,
          size: 72,
          color: AppColors.emerald,
        ),
      ),
    );
  }

  Widget _buildSpecTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.gray500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: AppColors.gray500)),
                Text(
                  value,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String label;
  const _FeatureChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.emeraldDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.obsidian,
            ),
          ),
        ],
      ),
    );
  }
}
