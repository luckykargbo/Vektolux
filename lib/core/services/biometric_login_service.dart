// lib/core/services/biometric_login_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Biometric login (Face ID / Touch ID / fingerprint).
// The operating system performs the biometric check and only reports success or failure:
// Vektolux never sees, captures, stores or uploads any face or fingerprint data. The only
// thing kept is a per-account on/off preference on this device.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric methods the device has enrolled, named as the platform names them.
enum BiometricMethod { faceId, touchId, faceUnlock, fingerprint, iris, deviceBiometrics }

extension BiometricMethodLabel on BiometricMethod {
  String get label => switch (this) {
        BiometricMethod.faceId => 'Face ID',
        BiometricMethod.touchId => 'Touch ID',
        BiometricMethod.faceUnlock => 'Face unlock',
        BiometricMethod.fingerprint => 'Fingerprint',
        BiometricMethod.iris => 'Iris',
        BiometricMethod.deviceBiometrics => 'Biometrics',
      };
}

/// "Face ID", "Touch ID", "Face unlock or Fingerprint", … for the methods present.
String biometricLabel(List<BiometricMethod> methods) =>
    methods.isEmpty ? 'Biometrics' : methods.map((m) => m.label).join(' or ');

class BiometricLoginService {
  final LocalAuthentication _auth;

  BiometricLoginService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  static String _key(String userId) => 'vx_biometric_login_$userId';

  /// Enrolled biometric methods. Empty when the device has none (or on web).
  Future<List<BiometricMethod>> availableMethods() async {
    if (kIsWeb) return const [];
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return const [];
      final types = await _auth.getAvailableBiometrics();
      final apple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
      final methods = <BiometricMethod>[
        if (types.contains(BiometricType.face)) apple ? BiometricMethod.faceId : BiometricMethod.faceUnlock,
        if (types.contains(BiometricType.fingerprint)) apple ? BiometricMethod.touchId : BiometricMethod.fingerprint,
        if (types.contains(BiometricType.iris)) BiometricMethod.iris,
      ];
      // Android may report only a strength class ("strong"/"weak") without naming the sensor.
      if (methods.isEmpty && (types.contains(BiometricType.strong) || types.contains(BiometricType.weak))) {
        methods.add(BiometricMethod.deviceBiometrics);
      }
      return methods;
    } catch (_) {
      // No plugin / no hardware / OS error: treated as "not available", never as enabled.
      return const [];
    }
  }

  Future<bool> isEnabled(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(String userId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(_key(userId), true);
    } else {
      await prefs.remove(_key(userId));
    }
  }

  /// Asks the OS to verify the enrolled biometric. Returns only success / failure.
  Future<bool> authenticate(String reason) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false; // any failure is a failed check
    }
  }
}
