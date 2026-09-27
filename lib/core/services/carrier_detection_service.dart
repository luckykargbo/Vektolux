// lib/core/services/carrier_detection_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Sierra Leone Mobile Money Carrier Auto-Detection Service
// Automatically parses MSISDN prefixes to route transactions to
// Orange Money (m17), Africell Afrimoney (m18), or QCell QMoney (m19).
//
// PREFIX RULES (2025 SL MSISDN PLAN):
//  • Orange  (m17): 07x → 071-079
//  • Africell (m18): 08x → 080-089, 09x → 090-099, legacy 077, 030, 033
//  • QCell   (m19): 03x → 030-039 (except 033 claimed by Africell), 031-039
//
// Manual tap-to-change override is supported via CarrierBadgeWidget.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

// ── Carrier Enum ─────────────────────────────────────────────────────
enum SierraLeoneCarrier {
  orange,
  africell,
  qmoney,
  unknown,
}

// ── Carrier Extension ─────────────────────────────────────────────────
extension SierraLeoneCarrierExtension on SierraLeoneCarrier {
  String get displayName {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return 'Orange Money';
      case SierraLeoneCarrier.africell:
        return 'Africell Afrimoney';
      case SierraLeoneCarrier.qmoney:
        return 'QCell QMoney';
      case SierraLeoneCarrier.unknown:
        return 'Select Network';
    }
  }

  String get shortName {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return 'Orange';
      case SierraLeoneCarrier.africell:
        return 'Afrimoney';
      case SierraLeoneCarrier.qmoney:
        return 'QMoney';
      case SierraLeoneCarrier.unknown:
        return 'Network?';
    }
  }

  /// Gateway provider slug used by Convex/MoniMe (legacy slug-based routing).
  String get providerSlug {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return 'orange';
      case SierraLeoneCarrier.africell:
        return 'africell';
      case SierraLeoneCarrier.qmoney:
        return 'qmoney';
      case SierraLeoneCarrier.unknown:
        return 'orange'; // default fallback
    }
  }

  /// MoniMe provider ID used in checkout/payout APIs.
  String get providerId {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return 'm17';
      case SierraLeoneCarrier.africell:
        return 'm18';
      case SierraLeoneCarrier.qmoney:
        return 'm19';
      case SierraLeoneCarrier.unknown:
        return 'm17'; // default fallback
    }
  }

  Color get brandColor {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return const Color(0xFFFF7900); // Orange Telecom Brand
      case SierraLeoneCarrier.africell:
        return const Color(0xFF7B1FA2); // Africell Magenta/Purple
      case SierraLeoneCarrier.qmoney:
        return const Color(0xFF008938); // QCell Emerald Green
      case SierraLeoneCarrier.unknown:
        return const Color(0xFF64748B); // Slate Gray
    }
  }

  Color get brandBgColor {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return const Color(0xFFFFF3E0);
      case SierraLeoneCarrier.africell:
        return const Color(0xFFF3E5F5);
      case SierraLeoneCarrier.qmoney:
        return const Color(0xFFE8F5E9);
      case SierraLeoneCarrier.unknown:
        return const Color(0xFFF1F5F9);
    }
  }

  IconData get iconData {
    switch (this) {
      case SierraLeoneCarrier.orange:
        return Icons.signal_cellular_alt_rounded;
      case SierraLeoneCarrier.africell:
        return Icons.cell_tower_rounded;
      case SierraLeoneCarrier.qmoney:
        return Icons.wifi_calling_3_rounded;
      case SierraLeoneCarrier.unknown:
        return Icons.phone_android_rounded;
    }
  }

  bool get isRecognized => this != SierraLeoneCarrier.unknown;
}

// ── Carrier Detection Service ─────────────────────────────────────────
class CarrierDetectionService {
  // ── Orange Money (m17): 07x (except 070 & 077 which are Africell) ──
  static const Set<String> _orangePrefixes = {
    '71', '72', '73', '74', '75', '76', '78', '79',
  };

  // ── Africell Afrimoney (m18):
  //    08x series (080-089), 09x series (090-099),
  //    legacy overrides: 077, 070, 030, 033
  static const Set<String> _africellPrefixes = {
    // 08x
    '80', '81', '82', '83', '84', '85', '86', '87', '88', '89',
    // 09x
    '90', '91', '92', '93', '94', '95', '96', '97', '98', '99',
    // legacy
    '70', '77', '30', '33',
  };

  // ── QCell QMoney (m19):
  //    03x (031-039) except 030 & 033 claimed by Africell
  static const Set<String> _qmoneyPrefixes = {
    '31', '32', '34', '35', '36', '37', '38', '39',
  };

  // ── Sanitize: strip non-digits ────────────────────────────────────
  static String sanitizeDigits(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  // ── Normalize to 232XXXXXXXX (11 digits) ──────────────────────────
  static String normalizeToSierraLeoneFormat(String? raw) {
    String d = sanitizeDigits(raw);
    if (d.isEmpty) return '';
    // Strip accidental double-zero prefix: 2320XXXXXXXX → 232XXXXXXXX
    if (d.startsWith('2320') && d.length == 12) return '232${d.substring(4)}';
    if (d.startsWith('232') && d.length >= 11) return d.substring(0, 11);
    if (d.startsWith('0') && d.length >= 9) return '232${d.substring(1, 9)}';
    if (d.length == 8) return '232$d';
    if (d.startsWith('232')) return d;
    return d;
  }

  // ── Extract 2-digit network prefix ───────────────────────────────
  static String extractNetworkPrefix(String? raw) {
    final d = sanitizeDigits(raw);
    if (d.isEmpty) return '';
    if (d.startsWith('2320') && d.length >= 6) return d.substring(4, 6);
    if (d.startsWith('232') && d.length >= 5) return d.substring(3, 5);
    if (d.startsWith('0') && d.length >= 3) return d.substring(1, 3);
    if (d.length >= 2) return d.substring(0, 2);
    return '';
  }

  // ── Core detection logic ──────────────────────────────────────────
  static SierraLeoneCarrier detectCarrier(String? raw) {
    final prefix = extractNetworkPrefix(raw);
    if (prefix.length < 2) return SierraLeoneCarrier.unknown;

    // Africell checked BEFORE orange so that '77' and '70' override correctly
    if (_africellPrefixes.contains(prefix)) return SierraLeoneCarrier.africell;
    if (_orangePrefixes.contains(prefix)) return SierraLeoneCarrier.orange;
    if (_qmoneyPrefixes.contains(prefix)) return SierraLeoneCarrier.qmoney;

    // Catch-all: any remaining 08x → Africell, 07x → Orange, 03x → QMoney
    if (prefix.startsWith('8') || prefix.startsWith('9')) return SierraLeoneCarrier.africell;
    if (prefix.startsWith('7')) return SierraLeoneCarrier.orange;
    if (prefix.startsWith('3')) return SierraLeoneCarrier.qmoney;

    return SierraLeoneCarrier.unknown;
  }

  // ── Format for display ────────────────────────────────────────────
  static String formatPhoneForDisplay(String? raw) {
    final norm = normalizeToSierraLeoneFormat(raw);
    if (norm.length == 11 && norm.startsWith('232')) {
      return '+${norm.substring(0, 3)} ${norm.substring(3, 5)} ${norm.substring(5, 8)} ${norm.substring(8, 11)}';
    }
    return raw ?? '';
  }
}

// ─────────────────────────────────────────────────────────────────────
// CarrierBadgeWidget
// Displays the detected carrier with:
//  • Animated brand pill (color, icon, name)
//  • Optional tap-to-override: opens a bottom-sheet to let the user
//    pick a different carrier (manual override lock).
// ─────────────────────────────────────────────────────────────────────
class CarrierBadgeWidget extends StatelessWidget {
  final SierraLeoneCarrier carrier;
  final bool compact;

  /// When non-null the badge becomes tappable and calls this on override.
  final ValueChanged<SierraLeoneCarrier>? onOverride;

  const CarrierBadgeWidget({
    super.key,
    required this.carrier,
    this.compact = false,
    this.onOverride,
  });

  Future<void> _showOverrideSheet(BuildContext context) async {
    final result = await showModalBottomSheet<SierraLeoneCarrier>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Network',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Override the auto-detected carrier for this number.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              for (final c in [
                SierraLeoneCarrier.orange,
                SierraLeoneCarrier.africell,
                SierraLeoneCarrier.qmoney,
              ]) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(ctx).pop(c),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: carrier == c ? c.brandBgColor : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: carrier == c
                            ? c.brandColor.withValues(alpha: 0.5)
                            : const Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: c.brandBgColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(c.iconData, size: 18, color: c.brandColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: c.brandColor,
                                ),
                              ),
                              Text(
                                'Provider ID: ${c.providerId}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                        if (carrier == c)
                          Icon(Icons.check_circle_rounded, color: c.brandColor, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
    if (result != null) {
      onOverride?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool tappable = onOverride != null;
    final bool show = carrier.isRecognized || tappable;
    if (!show) return const SizedBox.shrink();

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: carrier.brandBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: carrier.isRecognized
              ? carrier.brandColor.withValues(alpha: 0.5)
              : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            carrier.iconData,
            size: compact ? 12 : 14,
            color: carrier.brandColor,
          ),
          const SizedBox(width: 5),
          Text(
            compact ? carrier.shortName : carrier.displayName,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: carrier.brandColor,
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: compact ? 12 : 14,
              color: carrier.brandColor.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );

    if (!tappable) return badge;

    return GestureDetector(
      onTap: () => _showOverrideSheet(context),
      child: badge,
    );
  }
}
