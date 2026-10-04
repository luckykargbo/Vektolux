// Streaming uploads to Convex storage: real byte progress, the storage id as the only proof of
// success, and the listing media rules (limits, failed uploads never attached, retry, order).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/core/services/media_upload_service.dart';
import 'package:vektolux/features/agent/presentation/widgets/listing_media_editor.dart';

/// Convex (`files:generateUploadUrl`) answering with an upload URL, or an error.
ConvexClientWrapper _convex({String? error, List<String>? calls}) => ConvexClientWrapper(
      deploymentUrl: 'https://example.invalid',
      httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        calls?.add(body['path'] as String);
        if (error != null) return http.Response(jsonEncode({'status': 'error', 'errorMessage': error}), 200);
        return http.Response(jsonEncode({'status': 'success', 'value': 'https://upload.example.invalid/u?t=1'}), 200);
      }),
    );

Stream<List<int>> _chunks(int total, int size) async* {
  for (var sent = 0; sent < total; sent += size) {
    yield List.filled(sent + size > total ? total - sent : size, 7);
  }
}

void main() {
  group('MediaUploadService', () {
    test('streams the bytes with their type, reports real progress and returns the storage id', () async {
      String? type;
      int? received;
      final storage = MockClient((req) async {
        type = req.headers['content-type'];
        received = req.bodyBytes.length;
        return http.Response(jsonEncode({'storageId': 'kg_123'}), 200);
      });
      final progress = <int>[];
      final id = await MediaUploadService.upload(
        convexClient: _convex(),
        data: _chunks(300000, 64 * 1024),
        length: 300000,
        contentType: 'video/mp4',
        httpClient: storage,
        onProgress: (sent, total) {
          expect(total, 300000);
          progress.add(sent);
        },
      );
      expect(id, 'kg_123');
      expect(type, 'video/mp4');
      expect(received, 300000);
      expect(progress, isNotEmpty);
      expect(progress.last, 300000);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThan(progress[i - 1]));
      }
    });

    test('an HTTP failure or a missing storage id is an error, never a success', () async {
      for (final response in [http.Response('nope', 500), http.Response('{}', 200), http.Response('not json', 200)]) {
        await expectLater(
          MediaUploadService.upload(
            convexClient: _convex(),
            data: _chunks(10, 10),
            length: 10,
            contentType: 'image/jpeg',
            httpClient: MockClient((_) async => response),
          ),
          throwsA(isA<MediaUploadException>()),
        );
      }
    });

    test('when Convex refuses an upload URL (rate limit), its message is passed on and nothing is sent', () async {
      var sent = false;
      await expectLater(
        MediaUploadService.upload(
          convexClient: _convex(error: 'Uncaught Error: Upload limit reached. Please try again later.'),
          data: _chunks(10, 10),
          length: 10,
          contentType: 'image/jpeg',
          httpClient: MockClient((_) async {
            sent = true;
            return http.Response('{}', 200);
          }),
        ),
        throwsA(isA<MediaUploadException>().having((e) => e.message, 'message', contains('Upload limit reached'))),
      );
      expect(sent, isFalse);
    });

    test('content types: the picker type first, else the file extension', () {
      expect(mediaContentType('clip.MOV', video: true), 'video/quicktime');
      expect(mediaContentType('clip.mp4', video: true), 'video/mp4');
      expect(mediaContentType('photo.png', video: false), 'image/png');
      expect(mediaContentType('photo', video: false), 'image/jpeg');
      expect(mediaContentType('x.bin', reported: 'video/webm', video: true), 'video/webm');
    });
  });

  group('ListingMediaController', () {
    late List<int> failSizes;
    late List<String> received;

    ListingMediaController controller() {
      failSizes = [];
      received = [];
      return ListingMediaController(
        client: _convex(),
        httpClient: MockClient((req) async {
          final n = req.bodyBytes.length;
          received.add('${req.headers['content-type']}:$n');
          if (failSizes.remove(n)) return http.Response('down', 503);
          return http.Response(jsonEncode({'storageId': 'id_$n'}), 200);
        }),
      );
    }

    Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 60));

    XFile photo(int bytes) => XFile.fromData(Uint8List(bytes), name: 'p$bytes.jpg', path: 'p$bytes.jpg', mimeType: 'image/jpeg');
    XFile video(int bytes, {int? length}) =>
        XFile.fromData(Uint8List(bytes), name: 'v$bytes.mp4', path: 'v$bytes.mp4', mimeType: 'video/mp4', length: length);

    test('uploads photos and videos; only confirmed ids are attached, in display order', () async {
      final c = controller();
      await c.addPhotos([photo(100), photo(200)]);
      expect(await c.addVideo(video(5000)), isNull);
      await drain();
      expect(c.isUploading, isFalse);
      expect(c.uploadedPhotoIds, ['id_100', 'id_200']);
      expect(c.uploadedVideoIds, ['id_5000']);
      expect(received, containsAll(['image/jpeg:100', 'image/jpeg:200', 'video/mp4:5000']));
      expect(c.photos.every((p) => p.progress == 1), isTrue);

      c.makeCover(c.photos[1]);
      expect(c.uploadedPhotoIds, ['id_200', 'id_100']);
      c.reorderPhotos(0, 2);
      expect(c.uploadedPhotoIds, ['id_100', 'id_200']);
      c.remove(c.photos.first);
      expect(c.uploadedPhotoIds, ['id_200']);
      c.dispose();
    });

    test('a failed upload is never attached; retry uploads it again', () async {
      final c = controller();
      failSizes.add(300);
      await c.addPhotos([photo(300)]);
      await drain();
      expect(c.photos.single.state, ListingMediaState.failed);
      expect(c.photos.single.error, isNotNull);
      expect(c.uploadedPhotoIds, isEmpty);
      expect(c.failedCount, 1);

      c.retry(c.photos.single);
      await drain();
      expect(c.photos.single.state, ListingMediaState.uploaded);
      expect(c.uploadedPhotoIds, ['id_300']);
      expect(c.failedCount, 0);
      c.dispose();
    });

    test('limits are checked before uploading', () async {
      final c = controller();
      expect(await c.addVideo(video(10, length: kMaxListingVideoBytes + 1)), contains('at most 50 MB'));
      for (var i = 0; i < kMaxListingVideos; i++) {
        expect(await c.addVideo(video(10 + i)), isNull);
      }
      expect(await c.addVideo(video(99)), contains('up to $kMaxListingVideos videos'));
      final skipped = await c.addPhotos([for (var i = 0; i < kMaxListingPhotos + 2; i++) photo(1000 + i)]);
      expect(skipped, contains('up to $kMaxListingPhotos photos'));
      expect(c.photos, hasLength(kMaxListingPhotos));
      await drain();
      expect(received.where((r) => r.endsWith(':${kMaxListingVideoBytes + 1}')), isEmpty);
      c.dispose();
    });

    test('a removed upload that finishes later is ignored', () async {
      final c = controller();
      await c.addPhotos([photo(400)]);
      c.remove(c.photos.single);
      await drain();
      expect(c.photos, isEmpty);
      expect(c.uploadedPhotoIds, isEmpty);
      c.dispose();
    });
  });
}
