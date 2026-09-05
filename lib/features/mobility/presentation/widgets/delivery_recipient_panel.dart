// lib/features/mobility/presentation/widgets/delivery_recipient_panel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Delivery Recipient & Package Details Panel
// Dynamically revealed when user selects "Send Package / Delivery" mode.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class DeliveryRecipientPanel extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController notesController;
  final bool isFragile;
  final ValueChanged<bool> onFragileChanged;

  const DeliveryRecipientPanel({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.notesController,
    required this.isFragile,
    required this.onFragileChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.emerald.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  size: 16,
                  color: AppColors.emeraldDark,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Recipient & Parcel Specifications',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gray100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Required',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.gray600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. Recipient Name Field
          _buildInputField(
            controller: nameController,
            label: 'RECIPIENT FULL NAME',
            hint: 'e.g. Sahr Kamara',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 10),

          // 2. Recipient Phone Number Field (Sierra Leone Prefix)
          _buildPhoneField(),
          const SizedBox(height: 10),

          // 3. Package Description Field
          _buildInputField(
            controller: notesController,
            label: 'PACKAGE DESCRIPTION / DROP-OFF NOTES',
            hint: 'e.g. Important legal documents, sealed box',
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 12),

          // 4. Fragile Goods Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isFragile ? AppColors.amberSurface : AppColors.gray50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFragile
                    ? AppColors.amber.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: isFragile ? AppColors.amberDark : AppColors.gray500,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fragile / Handle With Care',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isFragile ? AppColors.amberDark : AppColors.obsidian,
                        ),
                      ),
                      Text(
                        'Alerts courier to secure parcel carefully',
                        style: TextStyle(
                          fontSize: 10,
                          color: isFragile ? AppColors.amberDark : AppColors.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isFragile,
                  activeThumbColor: AppColors.amber,
                  activeTrackColor: AppColors.amber.withValues(alpha: 0.3),
                  onChanged: onFragileChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.gray500,
            ),
          ),
          TextField(
            controller: controller,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.obsidian,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.gray400,
              ),
              border: InputBorder.none,
              prefixIcon: Icon(icon, size: 16, color: AppColors.emeraldDark),
              prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECIPIENT PHONE NUMBER',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.gray500,
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🇸🇱 ', style: TextStyle(fontSize: 11)),
                    Text(
                      '+232',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.obsidian,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    hintText: '76 123 456',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.gray400,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
