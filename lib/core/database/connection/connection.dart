// lib/core/database/connection/connection.dart
export 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart'
    if (dart.library.html) 'connection_web.dart';
