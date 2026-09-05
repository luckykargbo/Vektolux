// lib/core/theme/app_typography.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Design System Typography Scale
// Google Fonts: Inter (body/UI) + Poppins (display/headlines).
// Strict hierarchy following Material 3 type scale.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Vektolux typography scale using Inter and Poppins.
///
/// Hierarchy:
///   Display  → Hero sections, splash screens (Poppins Bold)
///   Headline → Section headers, page titles (Poppins SemiBold)
///   Title    → Card titles, dialog headers (Inter SemiBold)
///   Body     → Paragraphs, descriptions (Inter Regular)
///   Label    → Buttons, badges, captions (Inter Medium)
abstract final class AppTypography {
  // ─── Font Families ────────────────────────────────────────────────

  /// Display & headline font — geometric, modern feel.
  static const String _displayFont = 'Poppins';

  /// Body & UI font — clean, highly legible at small sizes.
  static const String _bodyFont = 'Inter';

  // ─── Complete TextTheme ───────────────────────────────────────────

  /// Material 3 TextTheme using the Vektolux type scale.
  static TextTheme get textTheme => const TextTheme(
        // ── Display ─────────────────────────────────────────────────
        displayLarge: TextStyle(
          fontFamily: _displayFont,
          fontSize: 57,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          height: 1.12,
          color: AppColors.textPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: _displayFont,
          fontSize: 45,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.16,
          color: AppColors.textPrimary,
        ),
        displaySmall: TextStyle(
          fontFamily: _displayFont,
          fontSize: 36,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.22,
          color: AppColors.textPrimary,
        ),

        // ── Headline ────────────────────────────────────────────────
        headlineLarge: TextStyle(
          fontFamily: _displayFont,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.25,
          color: AppColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: _displayFont,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.29,
          color: AppColors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: _displayFont,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.33,
          color: AppColors.textPrimary,
        ),

        // ── Title ───────────────────────────────────────────────────
        titleLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.27,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          height: 1.50,
          color: AppColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.43,
          color: AppColors.textPrimary,
        ),

        // ── Body ────────────────────────────────────────────────────
        bodyLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          height: 1.50,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          height: 1.43,
          color: AppColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
          height: 1.33,
          color: AppColors.textSecondary,
        ),

        // ── Label ───────────────────────────────────────────────────
        labelLarge: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          height: 1.43,
          color: AppColors.textPrimary,
        ),
        labelMedium: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          height: 1.33,
          color: AppColors.textPrimary,
        ),
        labelSmall: TextStyle(
          fontFamily: _bodyFont,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      );

  // ─── Custom Styles (beyond Material scale) ────────────────────────

  /// Price display — large, bold, emerald.
  static TextStyle get priceDisplay => const TextStyle(
        fontFamily: _displayFont,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.emerald,
      );

  /// Fare breakdown — medium mono-style for numbers.
  static TextStyle get fareAmount => const TextStyle(
        fontFamily: _bodyFont,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      );

  /// Badge text — compact, uppercase.
  static TextStyle get badge => const TextStyle(
        fontFamily: _bodyFont,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        height: 1.0,
      );

  /// Overline / section label.
  static TextStyle get overline => const TextStyle(
        fontFamily: _bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        height: 1.45,
        color: AppColors.textSecondary,
      );
}
