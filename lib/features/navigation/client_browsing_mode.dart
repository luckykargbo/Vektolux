// lib/features/navigation/client_browsing_mode.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — "Browse as a client" (Settings → Browse as a client).
// A session-only VIEW choice of a professional account: while it is on, the standard client app
// shows no posting / listing-management entry points. It grants and removes nothing — the same
// account stays signed in, and the server alone decides whether a listing may be created
// (approved role + active subscription, convex/lib/permissions.ts).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

class ClientBrowsingMode {
  ClientBrowsingMode._();

  /// Set by MainNavigationShell only.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool get isActive => active.value;
}
