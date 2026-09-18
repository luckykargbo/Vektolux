// lib/features/mobility/presentation/views/driver_vehicle_registration_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Commercial Vehicle & Fleet Registration (DEPRECATED & ARCHIVED)
// This partner registration flow has been safely deprecated and retired.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Deprecated commercial vehicle partner registration wizard.
/// Retained as a safe archived route to prevent broken routes or dangling references.
@Deprecated('Commercial vehicle partner registration flow has been decommissioned.')
class DriverVehicleRegistrationScreen extends StatelessWidget {
  final String driverId;
  final VoidCallback? onRegistrationComplete;

  const DriverVehicleRegistrationScreen({
    super.key,
    required this.driverId,
    this.onRegistrationComplete,
  });

  /// Safe backward-compatible navigation helper that pops or returns false.
  static Future<bool?> open(BuildContext context, {required String driverId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DriverVehicleRegistrationScreen(driverId: driverId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        title: const Text(
          'Registration Notice',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.obsidian.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Registration Flow Retired',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.obsidian,
                  fontFamily: 'Poppins',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'The standalone commercial vehicle & fleet registration wizard has been deprecated. '
                'To list showroom cars or auto dealer inventory, please use "Sell Vehicles as Auto Dealer". '
                'For properties and rentals, please use "List Properties as Real Estate Agent".',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.gray600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.obsidian,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text(
                    'Return',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
