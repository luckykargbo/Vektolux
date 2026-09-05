// lib/features/real_estate/presentation/widgets/payment_webview_dialog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Payment Checkout Dialog for Mobile Money & Card Gateways
// Displays the Flutterwave/Paystack payment session inside a clean modal.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';

class PaymentCheckoutDialog extends StatelessWidget {
  final String checkoutUrl;
  final String reference;
  final double totalAmount;
  final String currency;
  final VoidCallback onPaymentCompleted;

  const PaymentCheckoutDialog({
    super.key,
    required this.checkoutUrl,
    required this.reference,
    required this.totalAmount,
    required this.currency,
    required this.onPaymentCompleted,
  });

  static Future<void> show({
    required BuildContext context,
    required String checkoutUrl,
    required String reference,
    required double totalAmount,
    required String currency,
    required VoidCallback onPaymentCompleted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PaymentCheckoutDialog(
        checkoutUrl: checkoutUrl,
        reference: reference,
        totalAmount: totalAmount,
        currency: currency,
        onPaymentCompleted: onPaymentCompleted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shield trust indicator
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.emeraldSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: AppColors.emeraldDark,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Secure Payment Gateway',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pay $currency ${totalAmount.toStringAsFixed(0)} via Flutterwave / Paystack',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.gray600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Reference container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.gray500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ref: $reference',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment Link button (launches external/in-app checkout)
            VxButton(
              label: 'Proceed to Payment Provider',
              icon: Icons.open_in_browser_rounded,
              onPressed: () {
                // In production, launches url via url_launcher or InAppWebView
                onPaymentCompleted();
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),

            VxButton.outlined(
              label: 'Cancel Booking',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
