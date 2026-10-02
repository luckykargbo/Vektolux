// lib/core/constants/app_constants.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — App-Wide Constants
// ═══════════════════════════════════════════════════════════════════════

/// API and backend configuration constants.
abstract final class ApiConstants {
  /// Convex deployment URL.
  static const String convexUrl = String.fromEnvironment(
    'CONVEX_URL',
    defaultValue: 'https://ideal-poodle-813.convex.cloud',
  );

  // (No Paystack/Flutterwave: payments go through Monime / the Vektolux wallet on the server.)

  /// Blockchain RPC endpoints.
  static const String polygonRpc = 'https://polygon-rpc.com';
  static const String baseRpc = 'https://mainnet.base.org';

  /// HTTP timeout.
  static const Duration httpTimeout = Duration(seconds: 30);
}

/// UI layout constants.
abstract final class LayoutConstants {
  /// Standard horizontal padding for screens.
  static const double screenPaddingH = 16.0;

  /// Standard vertical padding for screens.
  static const double screenPaddingV = 24.0;

  /// Card border radius.
  static const double cardRadius = 16.0;

  /// Button border radius.
  static const double buttonRadius = 12.0;

  /// Bottom sheet top radius.
  static const double sheetRadius = 24.0;

  /// Map marker sizes.
  static const double markerSize = 48.0;

  /// Maximum content width (tablets / landscape).
  static const double maxContentWidth = 600.0;

  /// Bottom navigation bar height.
  static const double bottomNavHeight = 72.0;
}

/// Sync engine configuration.
abstract final class SyncConstants {
  /// Periodic sync interval.
  static const Duration syncInterval = Duration(seconds: 30);

  /// Convex subscription poll intervals per entity.
  static const Duration ridePollingInterval = Duration(seconds: 3);
  static const Duration propertyPollingInterval = Duration(seconds: 10);
  static const Duration walletPollingInterval = Duration(seconds: 15);
  static const Duration transactionPollingInterval = Duration(seconds: 30);

  /// Maximum outbox entries per sync batch.
  static const int maxBatchSize = 50;

  /// Maximum retry attempts before marking as failed.
  static const int maxRetries = 5;

  /// How long to keep synced entries before purging.
  static const Duration syncedRetention = Duration(hours: 24);
}

/// Feature flags.
abstract final class FeatureFlags {
  static const bool enableBlockchainLogging = true;
  static const bool enableMobileMoney = true;
  static const bool enableCryptoPayments = false; // Phase 2
  static const bool enableDarkMode = true;
  static const bool enableOfflineMode = true;
}

/// Currency & financial constants.
abstract final class FinancialConstants {
  /// Default currency code.
  static const String defaultCurrency = 'SLE';

  /// Default currency symbol.
  static const String currencySymbol = 'Le';

  /// Platform commission basis points per vertical.
  static const Map<String, int> commissionBps = {
    'property_sale': 250,
    'long_term_rent': 500,
    'hourly_guesthouse': 1000,
    'ride_hailing': 1500,
    'vehicle_rental': 800,
    'vehicle_sale': 300,
  };
}

/// Authentication & Google OAuth constants.
abstract final class AuthConstants {
  /// Google OAuth 2.0 Web Client ID (Vektolux Google Cloud Project).
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '489916570762-vfc729r27jha8q4s0o55piskj5a67bv3.apps.googleusercontent.com',
  );

  /// Google OAuth 2.0 iOS Client ID (bundle com.vektolux.app). Public identifier, not a secret.
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue:
        '489916570762-evp88rv2n0dqk1v41lhfl8aj7obl3gvi.apps.googleusercontent.com',
  );

  /// Google Cloud Project ID.
  static const String googleProjectId = 'vektolux';

  /// Google Cloud Project Number.
  static const String googleProjectNumber = '489916570762';
}

