// lib/core/theme/app_colors.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Design System Color Palette
// Material 3 color tokens with semantic naming.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Vektolux brand color palette.
///
/// Usage: `AppColors.emerald` or `AppColors.surface`
/// Never use raw hex values in widgets — always reference this class.
abstract final class AppColors {
  // ─── Primary Brand Colors ─────────────────────────────────────────

  /// Deep Slate Obsidian — primary dark, headers, nav bars.
  static const Color obsidian = Color(0xFF0F172A);

  /// Electric Emerald — trust, payments, success states, CTA buttons.
  static const Color emerald = Color(0xFF10B981);

  /// Warm Amber — active statuses, warnings, in-progress indicators.
  static const Color amber = Color(0xFFF59E0B);

  /// Crisp White — surfaces, cards, backgrounds.
  static const Color white = Color(0xFFFFFFFF);

  // ─── Extended Palette ─────────────────────────────────────────────

  /// Emerald shades for hover, pressed, and disabled states.
  static const Color emeraldLight = Color(0xFF34D399);
  static const Color emeraldDark = Color(0xFF059669);
  static const Color emeraldSurface = Color(0xFFECFDF5);

  /// Obsidian shades for layered surfaces.
  static const Color obsidianLight = Color(0xFF1E293B);
  static const Color obsidianMedium = Color(0xFF334155);
  static const Color obsidianSoft = Color(0xFF475569);

  /// Amber shades.
  static const Color amberLight = Color(0xFFFBBF24);
  static const Color amberDark = Color(0xFFD97706);
  static const Color amberSurface = Color(0xFFFFFBEB);

  // ─── Semantic Colors ──────────────────────────────────────────────

  /// Error / Danger — payment failures, validation errors.
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color errorDark = Color(0xFFDC2626);

  /// Info — informational badges, tooltips.
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  /// Success — completed transactions, verified badges.
  static const Color success = emerald;
  static const Color successLight = emeraldSurface;

  /// Warning — pending states, attention needed.
  static const Color warning = amber;
  static const Color warningLight = amberSurface;

  // ─── Neutral Grays ────────────────────────────────────────────────

  static const Color gray50 = Color(0xFFF8FAFC);
  static const Color gray100 = Color(0xFFF1F5F9);
  static const Color gray200 = Color(0xFFE2E8F0);
  static const Color gray300 = Color(0xFFCBD5E1);
  static const Color gray400 = Color(0xFF94A3B8);
  static const Color gray500 = Color(0xFF64748B);
  static const Color gray600 = Color(0xFF475569);
  static const Color gray700 = Color(0xFF334155);
  static const Color gray800 = Color(0xFF1E293B);
  static const Color gray900 = Color(0xFF0F172A);

  // ─── Surface & Background ─────────────────────────────────────────

  /// App background (light mode).
  static const Color background = gray50;

  /// Card / elevated surface.
  static const Color surface = white;

  /// Subtle surface for input fields, disabled areas.
  static const Color surfaceDim = gray100;

  /// Divider / border color.
  static const Color border = gray200;

  /// Scrim for modals and bottom sheets.
  static const Color scrim = Color(0x800F172A); // 50% obsidian

  // ─── Text Colors ──────────────────────────────────────────────────

  /// Primary text on light backgrounds.
  static const Color textPrimary = obsidian;

  /// Secondary / supporting text.
  static const Color textSecondary = gray500;

  /// Disabled / placeholder text.
  static const Color textDisabled = gray400;

  /// Text on dark / colored backgrounds.
  static const Color textOnDark = white;

  /// Text on emerald buttons.
  static const Color textOnEmerald = white;

  // ─── Vertical Accent Colors ───────────────────────────────────────

  /// Real Estate vertical accent.
  static const Color realEstate = Color(0xFF6366F1); // Indigo

  /// Mobility / Transportation vertical accent.
  static const Color mobility = Color(0xFF06B6D4); // Cyan

  /// Wallet / Payments vertical accent.
  static const Color wallet = emerald;

  // ─── Material 3 ColorScheme Builder ───────────────────────────────

  /// Generate the Material 3 light color scheme.
  static ColorScheme get lightScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: emerald,
        onPrimary: white,
        primaryContainer: emeraldSurface,
        onPrimaryContainer: emeraldDark,
        secondary: obsidian,
        onSecondary: white,
        secondaryContainer: gray100,
        onSecondaryContainer: obsidian,
        tertiary: amber,
        onTertiary: obsidian,
        tertiaryContainer: amberSurface,
        onTertiaryContainer: amberDark,
        error: error,
        onError: white,
        errorContainer: errorLight,
        onErrorContainer: errorDark,
        surface: white,
        onSurface: obsidian,
        surfaceContainerHighest: gray100,
        onSurfaceVariant: gray600,
        outline: gray300,
        outlineVariant: gray200,
        shadow: Color(0x1A0F172A),
        scrim: scrim,
        inverseSurface: obsidian,
        onInverseSurface: white,
        inversePrimary: emeraldLight,
      );

  /// Generate the Material 3 dark color scheme.
  static ColorScheme get darkScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: emeraldLight,
        onPrimary: obsidian,
        primaryContainer: emeraldDark,
        onPrimaryContainer: emeraldSurface,
        secondary: gray300,
        onSecondary: obsidian,
        secondaryContainer: obsidianMedium,
        onSecondaryContainer: gray100,
        tertiary: amberLight,
        onTertiary: obsidian,
        tertiaryContainer: amberDark,
        onTertiaryContainer: amberSurface,
        error: Color(0xFFF87171),
        onError: obsidian,
        errorContainer: Color(0xFF7F1D1D),
        onErrorContainer: errorLight,
        surface: obsidianLight,
        onSurface: gray100,
        surfaceContainerHighest: obsidianMedium,
        onSurfaceVariant: gray400,
        outline: gray600,
        outlineVariant: gray700,
        shadow: Color(0x40000000),
        scrim: Color(0xCC000000),
        inverseSurface: gray100,
        onInverseSurface: obsidian,
        inversePrimary: emeraldDark,
      );
}
