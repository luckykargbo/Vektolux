// lib/core/services/carrier_detection_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Sierra Leone Mobile Money Carrier Auto-Detection Service
// Automatically parses MSISDN prefixes to route transactions to
// Orange Money, Africell (Afrimoney), or QCell (QMoney) without manual selection.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

enum SierraLeoneCarrier {
  orange,
  africell,
  qmoney,
  unknown,
}

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
        return 'Enter SL Number';
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
        return 'Carrier';
    }
  }

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

class CarrierDetectionService {
  static const List<String> orangePrefixes = [
    '71', '72', '73', '74', '75', '76', '78', '79'
  ];

  static const List<String> africellPrefixes = [
    '70', '77', '80', '88', '90', '99', '30', '33'
  ];

  static const List<String> qmoneyPrefixes = [
    '31', '32', '34'
  ];

  /// Strips non-digits and returns sanitized digits.
  static String sanitizeDigits(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  /// Normalizes to standard 11-digit format `232XXXXXXXX`.
  static String normalizeToSierraLeoneFormat(String? raw) {
    String digits = sanitizeDigits(raw);
    if (digits.isEmpty) return '';

    if (digits.startsWith('2320') && digits.length == 12) {
      return '232${digits.substring(4)}';
    }
    if (digits.startsWith('232') && digits.length >= 11) {
      return digits.substring(0, 11);
    }
    if (digits.startsWith('0') && digits.length >= 9) {
      return '232${digits.substring(1, 9)}';
    }
    if (digits.length == 8) {
      return '232$digits';
    }
    if (digits.startsWith('232')) {
      return digits;
    }
    return digits;
  }

  /// Extracts the 2-digit network carrier prefix.
  static String extractNetworkPrefix(String? raw) {
    final digits = sanitizeDigits(raw);
    if (digits.isEmpty) return '';

    // If starts with 2320 (e.g. 232076123456)
    if (digits.startsWith('2320') && digits.length >= 6) {
      return digits.substring(4, 6);
    }
    // If starts with 232 (e.g. 23276123456)
    if (digits.startsWith('232') && digits.length >= 5) {
      return digits.substring(3, 5);
    }
    // If starts with 0 (e.g. 076123456)
    if (digits.startsWith('0') && digits.length >= 3) {
      return digits.substring(1, 3);
    }
    // If entered without leading 0 (e.g. 76123456)
    if (digits.length >= 2) {
      return digits.substring(0, 2);
    }
    return '';
  }

  /// Detects the Sierra Leone Carrier from phone string.
  static SierraLeoneCarrier detectCarrier(String? raw) {
    final prefix = extractNetworkPrefix(raw);
    if (prefix.length < 2) return SierraLeoneCarrier.unknown;

    if (orangePrefixes.contains(prefix)) {
      return SierraLeoneCarrier.orange;
    }
    if (africellPrefixes.contains(prefix)) {
      return SierraLeoneCarrier.africell;
    }
    if (qmoneyPrefixes.contains(prefix)) {
      return SierraLeoneCarrier.qmoney;
    }

    return SierraLeoneCarrier.unknown;
  }

  /// Formats phone nicely for display (e.g. `+232 76 123 456` or `076 123 456`).
  static String formatPhoneForDisplay(String? raw) {
    final norm = normalizeToSierraLeoneFormat(raw);
    if (norm.length == 11 && norm.startsWith('232')) {
      final code = norm.substring(0, 3);
      final pre = norm.substring(3, 5);
      final mid = norm.substring(5, 8);
      final end = norm.substring(8, 11);
      return '+$code $pre $mid $end';
    }
    return raw ?? '';
  }
}
