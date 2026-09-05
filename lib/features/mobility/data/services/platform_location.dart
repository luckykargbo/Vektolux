// lib/features/mobility/data/services/platform_location.dart
// ═══════════════════════════════════════════════════════════════════════
// Conditional export for cross-platform geolocation support.
// ═══════════════════════════════════════════════════════════════════════

export 'platform_location_stub.dart'
    if (dart.library.html) 'platform_location_web.dart';
