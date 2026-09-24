// lib/core/widgets/universal_phone_input.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Universal Sierra Leone Mobile Money Phone Input
// Single input field with real-time automatic carrier detection badge
// (Orange Money, Africell Afrimoney, QCell QMoney)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../services/carrier_detection_service.dart';

class UniversalPhoneInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
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
  SierraLeoneCarrier _currentCarrier = SierraLeoneCarrier.unknown;

  @override
  void initState() {
    super.initState();
    _currentCarrier = CarrierDetectionService.detectCarrier(widget.controller.text);
    widget.controller.addListener(_handlePhoneChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePhoneChanged);
    super.dispose();
  }

  void _handlePhoneChanged() {
    final carrier = CarrierDetectionService.detectCarrier(widget.controller.text);
    if (carrier != _currentCarrier) {
      setState(() {
        _currentCarrier = carrier;
      });
      widget.onCarrierChanged?.call(carrier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            // Live carrier badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _currentCarrier.brandBgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _currentCarrier.isRecognized
                      ? _currentCarrier.brandColor.withOpacity(0.5)
                      : AppColors.border,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _currentCarrier.iconData,
                    size: 13,
                    color: _currentCarrier.brandColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _currentCarrier.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _currentCarrier.brandColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
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
            suffixIcon: _currentCarrier.isRecognized
                ? Icon(Icons.check_circle_rounded, color: _currentCarrier.brandColor, size: 20)
                : null,
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _currentCarrier.isRecognized
                    ? _currentCarrier.brandColor.withOpacity(0.6)
                    : AppColors.border,
                width: _currentCarrier.isRecognized ? 1.5 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _currentCarrier.isRecognized ? _currentCarrier.brandColor : AppColors.emerald,
                width: 2.0,
              ),
            ),
          ),
        ),
        if (!_currentCarrier.isRecognized && widget.controller.text.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Enter a valid Sierra Leone number (071-079 Orange, 070/077/088 Africell, 031-034 QMoney)',
              style: TextStyle(fontSize: 11, color: AppColors.gray500),
            ),
          ),
      ],
    );
  }
}
