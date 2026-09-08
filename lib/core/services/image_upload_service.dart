// lib/core/services/image_upload_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Native Image & Cloud Media Upload Service
// Supports camera capture, device gallery picking, web file dialogs,
// and direct upload to Convex cloud storage with public URL resolution.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../constants/app_constants.dart';
import '../network/convex_client_wrapper.dart';

/// Result from uploading a file to Convex storage.
class ConvexUploadResult {
  final String storageId;
  final String publicUrl;

  const ConvexUploadResult({
    required this.storageId,
    required this.publicUrl,
  });
}

/// Image source selection options.
enum ImageSourceOption { camera, gallery, multiGallery }

/// Service responsible for native media selection and cloud uploads.
class ImageUploadService {
  static final ImagePicker _picker = ImagePicker();
  static final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Pick an image from the device photo gallery or web file selector.
  static Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      return file;
    } catch (e) {
      _log.e('Failed to pick image from gallery: $e');
      return null;
    }
  }

  /// Pick multiple images from the device gallery.
  static Future<List<XFile>> pickMultipleImages() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      return files;
    } catch (e) {
      _log.e('Failed to pick multiple images: $e');
      return [];
    }
  }

  /// Capture a new photo using the device camera.
  static Future<XFile?> pickImageFromCamera() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      return file;
    } catch (e) {
      _log.e('Failed to capture photo from camera: $e');
      return null;
    }
  }

  /// Show a bottom sheet modal to choose Camera vs Gallery (or Multiple).
  static Future<ImageSourceOption?> showImageSourceDialog(
    BuildContext context, {
    bool allowMulti = false,
  }) async {
    return showModalBottomSheet<ImageSourceOption>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Select Image Source',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: Color(0xFF059669)),
                ),
                title: const Text('Take Photo with Camera',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, ImageSourceOption.camera),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library, color: Color(0xFF059669)),
                ),
                title: Text(
                  allowMulti
                      ? 'Choose from Gallery (Multiple)'
                      : 'Choose from Gallery',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(
                  ctx,
                  allowMulti
                      ? ImageSourceOption.multiGallery
                      : ImageSourceOption.gallery,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Upload raw image bytes to Convex cloud storage and return both storageId and publicUrl.
  static Future<ConvexUploadResult> uploadImageBinaryWithStorageId({
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
      String resolvedUrl;
      final getUrlResult = await convexClient.query(
        'files:getFileUrl',
        args: {'storageId': storageId},
      );

      if (getUrlResult.success && getUrlResult.value != null) {
        resolvedUrl = getUrlResult.value as String;
      } else {
        final cleanBaseUrl = ApiConstants.convexUrl.replaceAll(RegExp(r'/+$'), '');
        resolvedUrl = '$cleanBaseUrl/api/storage/$storageId';
      }

      _log.i('Resolved public URL: $resolvedUrl');
      return ConvexUploadResult(storageId: storageId, publicUrl: resolvedUrl);
    } catch (e) {
      _log.e('Image upload failed: $e');
      rethrow;
    }
  }

  /// Upload raw image bytes to Convex cloud storage.
  /// Returns the resolved public URL of the uploaded asset.
  static Future<String> uploadImageToConvex({
    required ConvexClientWrapper convexClient,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    final result = await uploadImageBinaryWithStorageId(
      convexClient: convexClient,
      imageBytes: imageBytes,
      contentType: contentType,
    );
    return result.publicUrl;
  }
}
