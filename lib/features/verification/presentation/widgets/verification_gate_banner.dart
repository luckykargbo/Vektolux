// lib/features/verification/presentation/widgets/verification_gate_banner.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Listing Paywall & Identity Gate Banner
// Communicates requirement for sellers with instant verification CTA.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';

class VerificationGateBanner extends StatelessWidget {
  final VoidCallback onStartVerification;
  final String? pendingStatus;

  const VerificationGateBanner({
    super.key,
    required this.onStartVerification,
    this.pendingStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = pendingStatus == 'pending';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPending
            ? AppColors.amber.withValues(alpha: 0.08)
            : AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? AppColors.amber.withValues(alpha: 0.4)
              : AppColors.emerald.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPending
                      ? AppColors.amber.withValues(alpha: 0.2)
                      : AppColors.emerald.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPending ? Icons.hourglass_top_rounded : Icons.shield_rounded,
                  color: isPending ? AppColors.amber : AppColors.emerald,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPending
                          ? 'Verification Under Review'
                          : 'Identity Verification Required',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPending
                          ? 'Automated checks are processing. Takes ~30 seconds.'
                          : 'Unlock Property & Vehicle Listing Capabilities',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isPending
                ? 'Your submitted identity documents and biometric face match are being verified. Your Green Tick trust badge will activate automatically.'
                : 'To protect buyers and maintain platform integrity in Sierra Leone, all hosts, dealers, and landlords must verify their identity. Get your Green Tick badge to publish live listings.',
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.obsidian,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          VxButton.primary(
            text: isPending ? 'Check Live Status' : 'Verify Identity Now (2 Mins)',
            icon: isPending ? Icons.refresh_rounded : Icons.verified_user_rounded,
            onPressed: onStartVerification,
          ),
        ],
      ),
    );
  }
}
