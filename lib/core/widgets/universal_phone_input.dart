// lib/core/widgets/universal_phone_input.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Universal Sierra Leone Mobile Money Phone Input
// • Real-time prefix-based carrier auto-detection badge
// • Tap-to-override: user can manually select a different carrier
// • Manual override lock indicator (shows "overridden" pin icon)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../services/carrier_detection_service.dart';

class UniversalPhoneInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  /// Called whenever the effective carrier changes (auto or manual override).
  final void Function(SierraLeoneCarrier carrier)? onCarrierChanged;
  final bool enabled;

  const UniversalPhoneInput({
    super.key,
    required this.controller,
    this.label = 'Mobile Money Phone Number',
    this.hint = 'e.g. 076 123 456 or 077 123 456',
    this.onCarrierChanged,
    this.enabled = true,
  });

  @override
  State<UniversalPhoneInput> createState() => _UniversalPhoneInputState();
}

class _UniversalPhoneInputState extends State<UniversalPhoneInput> {
  SierraLeoneCarrier _autoDetectedCarrier = SierraLeoneCarrier.unknown;
  SierraLeoneCarrier? _manualOverride; // null = auto mode, set = locked override

  SierraLeoneCarrier get _effectiveCarrier =>
      _manualOverride ?? _autoDetectedCarrier;

  bool get _isOverridden => _manualOverride != null;

  @override
  void initState() {
    super.initState();
    _autoDetectedCarrier =
        CarrierDetectionService.detectCarrier(widget.controller.text);
    widget.controller.addListener(_handlePhoneChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePhoneChanged);
    super.dispose();
  }

  void _handlePhoneChanged() {
    // Only update auto-detection when not manually overridden
    final detected =
        CarrierDetectionService.detectCarrier(widget.controller.text);
    if (detected != _autoDetectedCarrier) {
      setState(() {
        _autoDetectedCarrier = detected;
      });
      if (!_isOverridden) {
        widget.onCarrierChanged?.call(detected);
      }
    }
  }

  void _applyOverride(SierraLeoneCarrier carrier) {
    setState(() {
      _manualOverride = carrier;
    });
    widget.onCarrierChanged?.call(carrier);
  }

  void _clearOverride() {
    setState(() {
      _manualOverride = null;
    });
    widget.onCarrierChanged?.call(_autoDetectedCarrier);
  }

  @override
  Widget build(BuildContext context) {
    final effective = _effectiveCarrier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Label row + carrier badge ──────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.obsidian,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clear override button
                if (_isOverridden)
                  GestureDetector(
                    onTap: _clearOverride,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded,
                              size: 10, color: Color(0xFFEA580C)),
                          SizedBox(width: 3),
                          Text(
                            'Override',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEA580C)),
                          ),
                          SizedBox(width: 3),
                          Icon(Icons.close_rounded,
                              size: 10, color: Color(0xFFEA580C)),
                        ],
                      ),
                    ),
                  ),
                // Tappable carrier badge
                CarrierBadgeWidget(
                  carrier: effective,
                  onOverride: widget.enabled ? _applyOverride : null,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Phone TextField ────────────────────────────────────────
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.phone,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.gray400,
            ),
            prefixIcon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: AppColors.border, width: 1.2),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🇸🇱', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 6),
                  Text(
                    '+232',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                ],
              ),
            ),
            suffixIcon: effective.isRecognized
                ? Icon(Icons.check_circle_rounded,
                    color: effective.brandColor, size: 20)
                : null,
            filled: true,
            fillColor: AppColors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: effective.isRecognized
                    ? effective.brandColor.withValues(alpha: 0.6)
                    : AppColors.border,
                width: effective.isRecognized ? 1.5 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: effective.isRecognized
                    ? effective.brandColor
                    : AppColors.emerald,
                width: 2.0,
              ),
            ),
          ),
        ),

        // ── Hint text ─────────────────────────────────────────────
        if (!effective.isRecognized && widget.controller.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 12, color: AppColors.gray500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Tap the network badge to manually select your carrier.',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.gray500),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
