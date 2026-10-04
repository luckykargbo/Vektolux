// lib/core/services/media_upload_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Streaming media upload to Convex storage with real progress.
//
// 1. files:generateUploadUrl (rate-limited, signed one-time URL)
// 2. the file is STREAMED to that URL (bounded memory, works for large videos); progress is the
//    number of bytes the network layer has actually consumed
// 3. the storage id returned by Convex is the only proof of success — a failed upload throws
//    [MediaUploadException]; nothing is ever reported as uploaded without that id.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../network/convex_client_wrapper.dart';

class MediaUploadException implements Exception {
  final String message;
  const MediaUploadException(this.message);

  @override
  String toString() => message;
}

/// A request whose body is a stream; [onProgress] fires as the transport consumes it.
class _StreamingUpload extends http.BaseRequest {
  final Stream<List<int>> _data;
  final void Function(int sent)? _onProgress;

  _StreamingUpload(Uri url, this._data, int length, this._onProgress) : super('POST', url) {
    contentLength = length;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    var sent = 0;
    return http.ByteStream(_data.map((chunk) {
      sent += chunk.length;
      _onProgress?.call(sent);
      return chunk;
    }));
  }
}

class MediaUploadService {
  MediaUploadService._();

  /// Uploads [length] bytes from [data] and returns the Convex storage id.
  static Future<String> upload({
    required ConvexClientWrapper convexClient,
    required Stream<List<int>> data,
    required int length,
    required String contentType,
    void Function(int sent, int total)? onProgress,
    http.Client? httpClient,
  }) async {
    final urlRes = await convexClient.mutation('files:generateUploadUrl');
    if (!urlRes.success || urlRes.value is! String || (urlRes.value as String).isEmpty) {
      throw MediaUploadException(urlRes.errorMessage ?? 'Could not start the upload. Please try again.');
    }
    final client = httpClient ?? http.Client();
    try {
      final request = _StreamingUpload(Uri.parse(urlRes.value as String), data, length, (sent) => onProgress?.call(sent, length))
        ..headers['Content-Type'] = contentType;
      final response = await client.send(request).timeout(const Duration(minutes: 10));
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MediaUploadException('Upload failed (HTTP ${response.statusCode}). Please try again.');
      }
      final decoded = jsonDecode(body);
      final storageId = decoded is Map ? decoded['storageId'] as String? : null;
      if (storageId == null || storageId.isEmpty) {
        throw const MediaUploadException('Upload failed: the server did not confirm the file.');
      }
      return storageId;
    } on MediaUploadException {
      rethrow;
    } catch (e) {
      throw MediaUploadException('Upload failed. Check your connection and try again.');
    } finally {
      if (httpClient == null) client.close();
    }
  }

  /// Public URL of an uploaded file (for previewing exactly what was stored).
  static Future<String?> fileUrl(ConvexClientWrapper convexClient, String storageId) async {
    final res = await convexClient.query('files:getFileUrl', args: {'storageId': storageId});
    return res.success && res.value is String ? res.value as String : null;
  }
}

/// MIME type from a file name (picker metadata is used first when available).
String mediaContentType(String name, {String? reported, required bool video}) {
  if (reported != null && reported.contains('/')) return reported;
  final lower = name.toLowerCase();
  if (video) {
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    return 'video/mp4';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}
