// lib/core/theme/app_theme.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Master Theme Configuration (Material 3)
// Assembles colors, typography, and component styles into ThemeData.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Provides light and dark ThemeData for the Vektolux app.
///
/// Usage in MaterialApp:
/// ```dart
/// MaterialApp(
///   theme: AppTheme.light,
///   darkTheme: AppTheme.dark,
///   themeMode: ThemeMode.system,
/// )
/// ```
abstract final class AppTheme {
  // ─── Shared Constants ─────────────────────────────────────────────

  static const double _borderRadius = 16.0;
  static const double _borderRadiusSm = 12.0;
  static const double _borderRadiusXs = 8.0;
  static const double _buttonHeight = 56.0;

  // ═══════════════════════════════════════════════════════════════════
  //                       LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════

  static ThemeData get light {
    final colorScheme = AppColors.lightScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: AppTypography.textTheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,

      // ── App Bar ─────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.obsidian,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.textTheme.titleLarge?.copyWith(
          color: AppColors.obsidian,
        ),
        iconTheme: const IconThemeData(
          color: AppColors.obsidian,
          size: 24,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.white,
        ),
      ),

      // ── Bottom Navigation ───────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.emerald,
        unselectedItemColor: AppColors.gray400,
        selectedLabelStyle: AppTypography.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.emerald,
        ),
        unselectedLabelStyle: AppTypography.textTheme.labelSmall,
        elevation: 8,
        showUnselectedLabels: true,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.emeraldSurface,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.emerald, size: 24);
          }
          return const IconThemeData(color: AppColors.gray400, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.textTheme.labelSmall?.copyWith(
              color: AppColors.emerald,
              fontWeight: FontWeight.w600,
            );
          }
          return AppTypography.textTheme.labelSmall?.copyWith(
            color: AppColors.gray500,
          );
        }),
        elevation: 3,
        surfaceTintColor: Colors.transparent,
        height: 72,
      ),

      // ── Cards ───────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Elevated Buttons (CTA) ──────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: AppColors.textOnEmerald,
          disabledBackgroundColor: AppColors.gray200,
          disabledForegroundColor: AppColors.gray400,
          elevation: 0,
          minimumSize: const Size(double.infinity, _buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadiusSm),
          ),
          textStyle: AppTypography.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),

      // ── Filled Buttons ──────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, _buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadiusSm),
          ),
          textStyle: AppTypography.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),

      // ── Outlined Buttons ────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.obsidian,
          minimumSize: const Size(double.infinity, _buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadiusSm),
          ),
          side: const BorderSide(color: AppColors.border, width: 1.5),
          textStyle: AppTypography.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),

      // ── Text Buttons ────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.emerald,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTypography.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input Fields ────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.gray100, // #F1F5F9
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
          borderSide: const BorderSide(color: AppColors.gray300, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
          borderSide: const BorderSide(color: AppColors.gray300, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
          borderSide: const BorderSide(color: AppColors.emerald, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: AppColors.gray500, // #64748B
        ),
        labelStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: AppColors.gray500, // #64748B
        ),
        errorStyle: AppTypography.textTheme.bodySmall?.copyWith(
          color: AppColors.error,
        ),
        prefixIconColor: AppColors.gray500,
        suffixIconColor: AppColors.gray500,
      ),

      // ── Chips ───────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.gray100,
        selectedColor: AppColors.emeraldSurface,
        disabledColor: AppColors.gray100,
        labelStyle: AppTypography.textTheme.labelMedium!,
        secondaryLabelStyle: AppTypography.textTheme.labelMedium!.copyWith(
          color: AppColors.emeraldDark,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadiusXs),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        showCheckmark: false,
      ),

      // ── Floating Action Button ──────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
      ),

      // ── Bottom Sheet ────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 8,
        dragHandleColor: AppColors.gray300,
        dragHandleSize: Size(40, 4),
        showDragHandle: true,
        modalElevation: 8,
        modalBackgroundColor: AppColors.white,
      ),

      // ── Dialogs ─────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: AppTypography.textTheme.headlineSmall,
        contentTextStyle: AppTypography.textTheme.bodyMedium,
      ),

      // ── Snack Bar ───────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.obsidian,
        contentTextStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: AppColors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
        ),
        elevation: 4,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // ── Divider ─────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Tab Bar ─────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        indicatorColor: AppColors.emerald,
        labelColor: AppColors.emerald,
        unselectedLabelColor: AppColors.gray500,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppTypography.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTypography.textTheme.labelLarge,
        dividerColor: AppColors.border,
      ),

      // ── Progress Indicators ─────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.emerald,
        linearTrackColor: AppColors.gray200,
        circularTrackColor: AppColors.gray200,
      ),

      // ── Switch ──────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.emerald;
          }
          return AppColors.gray400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.emeraldSurface;
          }
          return AppColors.gray200;
        }),
      ),

      // ── List Tile ───────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadiusXs),
        ),
        titleTextStyle: AppTypography.textTheme.titleSmall,
        subtitleTextStyle: AppTypography.textTheme.bodySmall,
        minVerticalPadding: 12,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       DARK THEME
  // ═══════════════════════════════════════════════════════════════════

  static ThemeData get dark {
    final colorScheme = AppColors.darkScheme;

    return light.copyWith(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.obsidian,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: AppColors.gray100,
        displayColor: AppColors.gray100,
      ),

      appBarTheme: light.appBarTheme.copyWith(
        backgroundColor: AppColors.obsidianLight,
        foregroundColor: AppColors.gray100,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.obsidian,
        ),
      ),

      cardTheme: light.cardTheme.copyWith(
        color: AppColors.obsidianLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          side: BorderSide(
            color: AppColors.gray700.withValues(alpha: 0.5),
          ),
        ),
      ),

      bottomNavigationBarTheme: light.bottomNavigationBarTheme.copyWith(
        backgroundColor: AppColors.obsidianLight,
      ),

      navigationBarTheme: light.navigationBarTheme.copyWith(
        backgroundColor: AppColors.obsidianLight,
        indicatorColor: AppColors.emeraldDark.withValues(alpha: 0.3),
      ),

      bottomSheetTheme: light.bottomSheetTheme.copyWith(
        backgroundColor: AppColors.obsidianLight,
        modalBackgroundColor: AppColors.obsidianLight,
        dragHandleColor: AppColors.gray600,
      ),

      dialogTheme: light.dialogTheme.copyWith(
        backgroundColor: AppColors.obsidianLight,
      ),

      inputDecorationTheme: light.inputDecorationTheme.copyWith(
        fillColor: AppColors.obsidianMedium,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadiusSm),
          borderSide: BorderSide(
            color: AppColors.gray700.withValues(alpha: 0.5),
          ),
        ),
      ),

      snackBarTheme: light.snackBarTheme.copyWith(
        backgroundColor: AppColors.gray800,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.gray700,
        thickness: 1,
      ),
    );
  }
}
