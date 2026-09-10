// lib/core/utils/safe_parser.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Safe Parsing & Casting Utilities
// Prevents runtime cast exceptions on untyped / dynamic Convex documents
// ═══════════════════════════════════════════════════════════════════════

/// Converts any dynamic value into a Map<String, dynamic>.
/// Returns an empty map if null or not a Map.
Map<String, dynamic> asStringKeyedMap(dynamic raw) {
  if (raw == null || raw is! Map) return <String, dynamic>{};
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

/// Converts any dynamic value into a List<String>.
/// Filters out null, empty, or whitespace-only elements.
List<String> asStringList(dynamic raw) {
  if (raw == null || raw is! Iterable) return <String>[];
  return raw
      .map((e) => e?.toString().trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Safely casts or parses a numeric value to double.
double asDouble(dynamic raw, [double fallback = 0.0]) {
  if (raw == null) return fallback;
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

/// Safely casts or parses a numeric value to int.
int asInt(dynamic raw, [int fallback = 0]) {
  if (raw == null) return fallback;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

/// Safely casts any dynamic value to a String.
String asString(dynamic raw, [String fallback = '']) {
  if (raw == null) return fallback;
  final str = raw.toString();
  return str.isEmpty ? fallback : str;
}

/// Safely casts any dynamic value to a bool.
bool asBool(dynamic raw, [bool fallback = false]) {
  if (raw == null) return fallback;
  if (raw is bool) return raw;
  if (raw is String) {
    final lower = raw.trim().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
  }
  if (raw is num) return raw != 0;
  return fallback;
}

/// Safely iterates over a dynamic list of Convex documents, mapping each
/// via [mapper]. Individual item parse exceptions are caught and skipped,
/// ensuring a single malformed record never aborts the entire dataset sync.
List<T> mapConvexList<T>(
  dynamic rawList,
  T? Function(Map<String, dynamic> map) mapper,
) {
  if (rawList == null || rawList is! Iterable) return <T>[];
  final result = <T>[];
  for (final item in rawList) {
    try {
      final map = asStringKeyedMap(item);
      if (map.isEmpty) continue;
      final parsed = mapper(map);
      if (parsed != null) {
        result.add(parsed);
      }
    } catch (_) {
      // Intentionally omit malformed document to avoid sync abortion
    }
  }
  return result;
}
