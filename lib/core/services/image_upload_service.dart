// lib/core/services/image_upload_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Native Image & Cloud Media Upload Service
// Supports camera capture, device gallery picking, web file dialogs,
// and direct upload to Convex cloud storage with public URL resolution.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../constants/app_constants.dart';
import '../network/convex_client_wrapper.dart';

/// Service responsible for native media selection and cloud uploads.
class ImageUploadService {
  static final ImagePicker _picker = ImagePicker();
  static final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Pick an image from the device photo gallery or web file selector.
  static Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      return file;
    } catch (e) {
      _log.e('Failed to pick image from gallery: $e');
      return null;
    }
  }

  /// Capture a new photo using the device camera.
  static Future<XFile?> pickImageFromCamera() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      return file;
    } catch (e) {
      _log.e('Failed to capture photo from camera: $e');
      return null;
    }
  }

  /// Upload raw image bytes to Convex cloud storage.
  /// Returns the resolved public URL of the uploaded asset.
  static Future<String> uploadImageToConvex({
    required ConvexClientWrapper convexClient,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    try {
      _log.i('Requesting signed upload URL from Convex...');
      // 1. Obtain signed upload URL
      final urlResult = await convexClient.mutation(
        'files:generateUploadUrl',
        args: {},
      );

      if (!urlResult.success || urlResult.value == null) {
        throw Exception(
          urlResult.errorMessage ?? 'Failed to generate Convex upload URL',
        );
      }

      final uploadUrl = urlResult.value as String;
      _log.i('Uploading ${imageBytes.lengthInBytes} bytes to Convex storage...');

      // 2. HTTP POST bytes to the signed storage URL
      final response = await http.post(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': contentType},
        body: imageBytes,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Convex storage upload failed with HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final storageId = data['storageId'] as String?;

      if (storageId == null || storageId.isEmpty) {
        throw Exception('No storageId returned from Convex storage upload');
      }

      _log.i('Storage ID received: $storageId. Resolving public file URL...');

      // 3. Resolve public URL via Convex files:getFileUrl query
      final getUrlResult = await convexClient.query(
        'files:getFileUrl',
        args: {'storageId': storageId},
      );

      if (getUrlResult.success && getUrlResult.value != null) {
        final resolvedUrl = getUrlResult.value as String;
        _log.i('Resolved public URL: $resolvedUrl');
        return resolvedUrl;
      }

      // 4. Fallback direct storage URL construction
      final cleanBaseUrl = ApiConstants.convexUrl.replaceAll(RegExp(r'/+$'), '');
      final fallbackUrl = '$cleanBaseUrl/api/storage/$storageId';
      _log.i('Using direct storage URL fallback: $fallbackUrl');
      return fallbackUrl;
    } catch (e) {
      _log.e('Image upload failed: $e');
      rethrow;
    }
  }
}
