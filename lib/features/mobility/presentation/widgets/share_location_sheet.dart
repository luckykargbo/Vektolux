// lib/features/mobility/presentation/widgets/share_location_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Direct Location Sharing Sheet (Sierra Leone)
// Generates deep link & WhatsApp/SMS shareable location payload for
// pinned or real-time GPS coordinates.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';

class ShareLocationSheet extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String label;
  final String? recipientName;

  const ShareLocationSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
    this.recipientName,
  });

  static Future<void> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    required String label,
    String? recipientName,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShareLocationSheet(
        latitude: latitude,
        longitude: longitude,
        label: label,
        recipientName: recipientName,
      ),
    );
  }

  String get _shareUrl =>
      'https://vektolux.com/map?lat=${latitude.toStringAsFixed(4)}&lng=${longitude.toStringAsFixed(4)}&label=${Uri.encodeComponent(label)}';

  String get _googleMapsFallback =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Drag Handle ───────────────────────────────────────────
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

          // ── Header ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.share_location_rounded,
                  color: AppColors.emeraldDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipientName != null
                          ? 'Share Location with $recipientName'
                          : 'Share Pinned Location',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Send real-time GPS coordinates via WhatsApp or SMS',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.gray500),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Coordinates Card ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin_drop_rounded, color: AppColors.emerald, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'GPS: ${latitude.toStringAsFixed(5)}° N, ${longitude.toStringAsFixed(5)}° W (Sierra Leone)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Courier',
                    color: AppColors.gray600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Copy Link Box ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gray300),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: AppColors.gray500, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _shareUrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier',
                      color: AppColors.obsidian,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: AppColors.emeraldDark, size: 20),
                  tooltip: 'Copy Link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _shareUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vektolux map link copied to clipboard!'),
                        backgroundColor: AppColors.emerald,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Actions: WhatsApp & SMS ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: VxButton.outlined(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  height: 48,
                  onPressed: () {
                    final message = 'My location on Vektolux ($label):\n$_shareUrl\n\nGoogle Maps:\n$_googleMapsFallback';
                    Clipboard.setData(ClipboardData(text: message));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Location text copied for WhatsApp!'),
                        backgroundColor: AppColors.emerald,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: VxButton.primary(
                  text: 'Share via SMS',
                  icon: Icons.sms_outlined,
                  height: 48,
                  onPressed: () {
                    final message = 'My location: $label - $_shareUrl';
                    Clipboard.setData(ClipboardData(text: message));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Location text copied for SMS!'),
                        backgroundColor: AppColors.emerald,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
