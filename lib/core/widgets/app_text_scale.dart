// lib/core/widgets/app_text_scale.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — App-wide text scaling.
// The phone's font-size setting (iOS Dynamic Type / Android font size) is honoured up to
// [kMaxAppTextScale]; larger settings are capped so every screen keeps its layout on small
// phones. Applied once around the whole app (MaterialApp.builder), so dialogs and bottom sheets
// follow the same rule.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/widgets.dart';

/// Largest text scale the app renders (the same cap the Home, Explore and agent screens use).
const double kMaxAppTextScale = 1.15;

class AppTextScale extends StatelessWidget {
  final Widget child;
  const AppTextScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: kMaxAppTextScale, child: child);
}
