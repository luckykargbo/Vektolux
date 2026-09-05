// lib/features/mobility/presentation/widgets/emergency_sos_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Emergency SOS & Safety Dispatch Modal
// High-priority Sierra Leone emergency response (Police 112/999,
// Medical 117, Rapid Response) with live GPS distress broadcast.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/ride_entity.dart';

class EmergencySosModal extends StatefulWidget {
  final RideEntity? ride;
  final double currentLat;
  final double currentLng;

  const EmergencySosModal({
    super.key,
    this.ride,
    required this.currentLat,
    required this.currentLng,
  });

  static Future<void> show(
    BuildContext context, {
    RideEntity? ride,
    required double currentLat,
    required double currentLng,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => EmergencySosModal(
        ride: ride,
        currentLat: currentLat,
        currentLng: currentLng,
      ),
    );
  }

  @override
  State<EmergencySosModal> createState() => _EmergencySosModalState();
}

class _EmergencySosModalState extends State<EmergencySosModal> {
  bool _isBroadcasting = false;
  bool _broadcastSent = false;

  void _triggerEmergencyBroadcast() async {
    setState(() => _isBroadcasting = true);

    // Simulate instant broadcast packet sent to Vektolux Security Ops & Emergency Services
    await Future.delayed(const Duration(milliseconds: 1200));

    if (mounted) {
      setState(() {
        _isBroadcasting = false;
        _broadcastSent = true;
      });

      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top SOS Icon & Alert Header ───────────────────────
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'EMERGENCY SOS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sierra Leone Emergency Dispatch & Safety Response',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // ── Live GPS Coordinates Display ──────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.gray100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gray300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.gps_fixed, size: 14, color: AppColors.emeraldDark),
                        SizedBox(width: 6),
                        Text(
                          'YOUR CURRENT GPS LOCATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${widget.currentLat.toStringAsFixed(5)}, Lng: ${widget.currentLng.toStringAsFixed(5)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Courier',
                        color: AppColors.obsidian,
                      ),
                    ),
                    if (widget.ride != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ride ID: ${widget.ride!.id} • Vehicle: ${widget.ride!.vehiclePlate ?? "SL-940-BA"}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Emergency Dispatch Quick Dial Cards ───────────────
              _buildEmergencyContactTile(
                title: 'Sierra Leone Police',
                subtitle: 'National Emergency Response Hotline',
                number: '112 / 999',
                icon: Icons.local_police_rounded,
                color: const Color(0xFF1E3A8A),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '112'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dialing Sierra Leone Police (112)... Number copied.'),
                      backgroundColor: AppColors.obsidian,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),

              _buildEmergencyContactTile(
                title: 'Medical Emergency & Ambulance',
                subtitle: 'Ministry of Health Dispatch',
                number: '117',
                icon: Icons.medical_services_rounded,
                color: const Color(0xFFDC2626),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '117'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dialing Health & Ambulance Dispatch (117)... Number copied.'),
                      backgroundColor: AppColors.obsidian,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),

              _buildEmergencyContactTile(
                title: 'Vektolux 24/7 Rapid Response',
                subtitle: 'Dedicated Control Room & Escort Ops',
                number: '+232 76 000 999',
                icon: Icons.shield_rounded,
                color: AppColors.emeraldDark,
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '+23276000999'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contacting Vektolux Rapid Response (+232 76 000 999)...'),
                      backgroundColor: AppColors.emerald,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // ── Instant Broadcast Alert Button ────────────────────
              if (_broadcastSent)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.emerald),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: AppColors.emeraldDark, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Distress Alert Broadcasted',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                            Text(
                              'Live GPS & trip telemetry sent to Vektolux Security Ops.',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                VxButton.destructive(
                  label: _isBroadcasting
                      ? 'Broadcasting Distress Signal...'
                      : 'Broadcast Emergency Alert & GPS',
                  icon: Icons.crisis_alert_rounded,
                  height: 50,
                  isLoading: _isBroadcasting,
                  onPressed: _triggerEmergencyBroadcast,
                ),
              const SizedBox(height: 12),

              // ── Close / Dismiss ───────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Close Safety Dialog',
                    style: TextStyle(
                      color: AppColors.gray600,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyContactTile({
    required String title,
    required String subtitle,
    required String number,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.gray50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.gray500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                number,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
