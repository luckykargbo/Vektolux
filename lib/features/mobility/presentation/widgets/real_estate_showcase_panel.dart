// lib/features/mobility/presentation/widgets/real_estate_showcase_panel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Showcase Panel
// Displays verified Sierra Leone property sales, rentals, and hourly
// guest houses within the multi-vertical primary navigation shell.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/theme/components/vx_status_badge.dart';
import '../../../../core/widgets/branded_media_fallback.dart';
import '../../../real_estate/domain/entities/property_listing_entity.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';

class RealEstateShowcasePanel extends StatefulWidget {
  final List<PropertyListingEntity> properties;
  final ValueChanged<PropertyListingEntity>? onBookSiteVisit;
  final ValueChanged<PropertyListingEntity>? onBookHourlyStay;

  const RealEstateShowcasePanel({
    super.key,
    required this.properties,
    this.onBookSiteVisit,
    this.onBookHourlyStay,
  });

  @override
  State<RealEstateShowcasePanel> createState() => _RealEstateShowcasePanelState();
}

class _RealEstateShowcasePanelState extends State<RealEstateShowcasePanel> {
  String _selectedCategory = 'all';

  List<PropertyListingEntity> get _filteredProperties {
    if (_selectedCategory == 'all') return widget.properties;
    return widget.properties.where((p) {
      if (_selectedCategory == 'sale') return p.category == RealEstateCategory.sale;
      if (_selectedCategory == 'rent') return p.category == RealEstateCategory.longTermRent;
      if (_selectedCategory == 'hourly') return p.category == RealEstateCategory.hourlyGuestHouse;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filter Chips Bar ──────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterChip('all', 'All Properties (${widget.properties.length})'),
              const SizedBox(width: 8),
              _buildFilterChip('sale', 'For Sale'),
              const SizedBox(width: 8),
              _buildFilterChip('rent', 'Long-Term Rent'),
              const SizedBox(width: 8),
              _buildFilterChip('hourly', 'Hourly Guest Houses'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Property Cards List ───────────────────────────────────────
        if (_filteredProperties.isEmpty)
          Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.home_work_outlined, size: 48, color: AppColors.gray400),
                  SizedBox(height: 12),
                  Text(
                    'No properties in this category yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.obsidian,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Check back shortly for newly verified listings.',
                    style: TextStyle(fontSize: 12, color: AppColors.gray500),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredProperties.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final prop = _filteredProperties[index];
              return _buildPropertyCard(context, prop);
            },
          ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedCategory == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.obsidian : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.obsidian : AppColors.gray300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.obsidian.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.white : AppColors.obsidian,
          ),
        ),
      ),
    );
  }

  Widget _buildPropertyCard(BuildContext context, PropertyListingEntity prop) {
    final isHourly = prop.category == RealEstateCategory.hourlyGuestHouse;
    final isRent = prop.category == RealEstateCategory.longTermRent;

    String priceLabel;
    if (isHourly) {
      priceLabel = 'SLE ${(prop.hourlyRate ?? prop.price).toStringAsFixed(0)} / hr';
    } else if (isRent) {
      priceLabel = 'SLE ${prop.price.toStringAsFixed(0)} / mo';
    } else {
      priceLabel = 'SLE ${prop.price.toStringAsFixed(0)}';
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen.fromEntity(prop),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image Header & Badges ─────────────────────────────────
          Stack(
            children: [
              SizedBox(
                height: 160,
                width: double.infinity,
                child: prop.imageUrls.isNotEmpty && prop.imageUrls.first.isNotEmpty
                    ? Image.network(
                        prop.imageUrls.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => brandedMediaFallback(
                          icon: Icons.apartment_rounded,
                          banner: prop.category.name,
                          height: 160,
                        ),
                      )
                    : brandedMediaFallback(
                        icon: Icons.apartment_rounded,
                        banner: prop.category.name,
                        height: 160,
                      ),
              ),

              // Category Badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    prop.category.displayName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),

              // Verified Badge
              if (prop.isVerified)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emerald,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 12, color: AppColors.white),
                        SizedBox(width: 4),
                        Text(
                          'Verified Deed',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // ── Details Body ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Price & Views
                Row(
                  children: [
                    Text(
                      priceLabel,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const Spacer(),
                    VxStatusBadge(
                      label: prop.availabilityStatus.toUpperCase(),
                      status: VxBadgeStatus.active,
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Title
                Text(
                  prop.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Address
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.gray500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        prop.address,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Specs: Beds, Baths, Area
                Row(
                  children: [
                    if (prop.bedrooms != null) ...[
                      _buildSpecChip(Icons.bed_rounded, '${prop.bedrooms} Beds'),
                      const SizedBox(width: 8),
                    ],
                    if (prop.bathrooms != null) ...[
                      _buildSpecChip(Icons.bathtub_outlined, '${prop.bathrooms} Baths'),
                      const SizedBox(width: 8),
                    ],
                    if (prop.areaSqM != null) ...[
                      _buildSpecChip(Icons.square_foot_rounded, '${prop.areaSqM!.toStringAsFixed(0)} m²'),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // Actions CTA
                Row(
                  children: [
                    Expanded(
                      child: isHourly
                          ? VxButton.primary(
                              text: 'Book Hourly Stay',
                              icon: Icons.access_time_filled_rounded,
                              height: 44,
                              onPressed: () {
                                if (widget.onBookHourlyStay != null) {
                                  widget.onBookHourlyStay!(prop);
                                } else {
                                  _showGenericBookingConfirm(context, prop, 'Hourly Stay');
                                }
                              },
                            )
                          : VxButton.primary(
                              text: 'Schedule Site Visit',
                              icon: Icons.calendar_today_rounded,
                              height: 44,
                              onPressed: () {
                                if (widget.onBookSiteVisit != null) {
                                  widget.onBookSiteVisit!(prop);
                                } else {
                                  _showGenericBookingConfirm(context, prop, 'Site Inspection Visit');
                                }
                              },
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildSpecChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.gray600),
          const SizedBox(width: 4),
          Text(
            text,
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

  void _showGenericBookingConfirm(BuildContext context, PropertyListingEntity prop, String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 26),
            const SizedBox(width: 8),
            Text('$type Confirmed', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Text(
          'Your $type for "${prop.title}" has been registered with ${prop.ownerName ?? "the property owner"}.\n\nLocation: ${prop.address}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done', style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
