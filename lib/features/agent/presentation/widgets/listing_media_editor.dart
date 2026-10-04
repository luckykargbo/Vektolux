// lib/features/agent/presentation/widgets/listing_media_editor.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Listing media (photos + videos) for the agent's Add Listing flow.
// Every file goes to the existing Convex storage (files:generateUploadUrl) with real byte
// progress. Only a storage id returned by Convex counts as uploaded: a failed upload shows its
// error with Retry and is never attached to the listing. A video preview plays the stored file.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/media_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_video_player.dart';
import 'agent_ui.dart';

const int kMaxListingPhotos = 15;

/// The server accepts at most 3 videos per listing.
const int kMaxListingVideos = 3;

/// Client-side caps. Convex gives an upload request 2 minutes, so clips stay short enough to
/// finish on a mobile connection (the server's own hard limit is 150 MB).
const int kMaxListingVideoBytes = 50 * 1024 * 1024;
const int kMaxListingPhotoBytes = 15 * 1024 * 1024;
const Duration kMaxListingVideoDuration = Duration(seconds: 60);

enum ListingMediaKind { photo, video }

enum ListingMediaState { uploading, uploaded, failed }

class ListingMediaItem {
  final String key;
  final ListingMediaKind kind;
  final XFile file;
  final int bytes;
  final String contentType;

  /// Photos only: the (picker-compressed) bytes that are uploaded, shown as the thumbnail.
  final Uint8List? thumbnail;

  ListingMediaState state = ListingMediaState.uploading;
  double progress = 0;
  String? storageId;
  String? error;
  int _attempt = 0;

  ListingMediaItem._(this.key, this.kind, this.file, this.bytes, this.contentType, this.thumbnail);

  bool get isUploaded => state == ListingMediaState.uploaded && storageId != null;
}

/// Picks files from the device. Replaced by a fake in tests.
abstract class ListingMediaSource {
  Future<List<XFile>> pickPhotos(BuildContext context, {required int max});
  Future<XFile?> pickVideo(BuildContext context);
}

class DeviceListingMediaSource implements ListingMediaSource {
  const DeviceListingMediaSource();

  static final ImagePicker _picker = ImagePicker();

  @override
  Future<List<XFile>> pickPhotos(BuildContext context, {required int max}) async {
    final source = await _chooseSource(context, video: false);
    if (source == null) return const [];
    if (source == ImageSource.camera) {
      final f = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      return f == null ? const [] : [f];
    }
    final files = await _picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    return files.length > max ? files.sublist(0, max) : files;
  }

  @override
  Future<XFile?> pickVideo(BuildContext context) async {
    final source = await _chooseSource(context, video: true);
    if (source == null) return null;
    return _picker.pickVideo(source: source, maxDuration: kMaxListingVideoDuration);
  }

  static Future<ImageSource?> _chooseSource(BuildContext context, {required bool video}) {
    Widget option(BuildContext ctx, IconData icon, String label, ImageSource value) => ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.emeraldSurface, child: Icon(icon, color: AppColors.emeraldDark)),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
          onTap: () => Navigator.of(ctx).pop(value),
        );
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(ctx, video ? Icons.videocam_outlined : Icons.photo_camera_outlined, video ? 'Record video' : 'Take photo',
                  ImageSource.camera),
              option(ctx, video ? Icons.video_library_outlined : Icons.photo_library_outlined,
                  video ? 'Choose a video' : 'Choose photos', ImageSource.gallery),
            ],
          ),
        ),
      ),
    );
  }
}

/// Upload state for the listing's photos and videos.
class ListingMediaController extends ChangeNotifier {
  final ConvexClientWrapper client;

  /// Transport for the uploads (tests); by default each upload uses its own client.
  final http.Client? httpClient;

  ListingMediaController({required this.client, this.httpClient});

  final List<ListingMediaItem> _photos = [];
  final List<ListingMediaItem> _videos = [];
  int _seq = 0;
  bool _disposed = false;
  String? _notice;

  /// A short message about the last add (a limit, an unreadable file), shown inline.
  String? get notice => _notice;

  void setNotice(String? message) {
    if (_notice == message) return;
    _notice = message;
    _changed();
  }

  List<ListingMediaItem> get photos => List.unmodifiable(_photos);
  List<ListingMediaItem> get videos => List.unmodifiable(_videos);
  Iterable<ListingMediaItem> get _all => [..._photos, ..._videos];

  bool get isUploading => _all.any((m) => m.state == ListingMediaState.uploading);
  int get failedCount => _all.where((m) => m.state == ListingMediaState.failed).length;
  bool get hasPhoto => _photos.isNotEmpty;

  /// Storage ids of the files Convex confirmed, in display order (the first photo is the cover).
  List<String> get uploadedPhotoIds => [for (final p in _photos) if (p.isUploaded) p.storageId!];
  List<String> get uploadedVideoIds => [for (final v in _videos) if (v.isUploaded) v.storageId!];

  Uint8List? get coverThumbnail {
    for (final p in _photos) {
      if (p.isUploaded) return p.thumbnail;
    }
    return null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Adds and uploads photos. Returns a message about skipped files, or null.
  Future<String?> addPhotos(List<XFile> files) async {
    String? skipped;
    for (final f in files) {
      if (_photos.length >= kMaxListingPhotos) {
        skipped = 'A listing can have up to $kMaxListingPhotos photos.';
        break;
      }
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        skipped = 'A photo could not be read.';
        continue;
      }
      if (bytes.length > kMaxListingPhotoBytes) {
        skipped = 'A photo was larger than 15 MB and was skipped.';
        continue;
      }
      final item = ListingMediaItem._('photo-${++_seq}', ListingMediaKind.photo, f, bytes.length,
          mediaContentType(f.name, reported: f.mimeType, video: false), bytes);
      _photos.add(item);
      _changed();
      unawaited(_upload(item));
    }
    return skipped;
  }

  /// Adds and uploads a video. Returns a message when it cannot be added, or null.
  Future<String?> addVideo(XFile file) async {
    if (_videos.length >= kMaxListingVideos) return 'A listing can have up to $kMaxListingVideos videos.';
    final length = await file.length();
    if (length <= 0) return 'The video could not be read.';
    if (length > kMaxListingVideoBytes) return 'Videos can be at most 50 MB. Choose a shorter clip.';
    final item = ListingMediaItem._('video-${++_seq}', ListingMediaKind.video, file, length,
        mediaContentType(file.name, reported: file.mimeType, video: true), null);
    _videos.add(item);
    _changed();
    unawaited(_upload(item));
    return null;
  }

  void retry(ListingMediaItem item) {
    if (item.state != ListingMediaState.failed) return;
    unawaited(_upload(item));
  }

  void remove(ListingMediaItem item) {
    item._attempt++; // a running upload's result is ignored
    _photos.remove(item);
    _videos.remove(item);
    _changed();
  }

  void reorderPhotos(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _photos.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _photos.removeAt(oldIndex);
    _photos.insert(newIndex.clamp(0, _photos.length), item);
    _changed();
  }

  void makeCover(ListingMediaItem item) {
    final i = _photos.indexOf(item);
    if (i > 0) reorderPhotos(i, 0);
  }

  Stream<List<int>> _photoChunks(Uint8List bytes) async* {
    const size = 64 * 1024;
    for (var i = 0; i < bytes.length; i += size) {
      yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
    }
  }

  Future<void> _upload(ListingMediaItem item) async {
    final attempt = ++item._attempt;
    item
      ..state = ListingMediaState.uploading
      ..progress = 0
      ..error = null
      ..storageId = null;
    _changed();
    var lastShown = 0.0;
    try {
      final id = await MediaUploadService.upload(
        convexClient: client,
        data: item.kind == ListingMediaKind.photo ? _photoChunks(item.thumbnail!) : item.file.openRead(),
        length: item.bytes,
        contentType: item.contentType,
        httpClient: httpClient,
        onProgress: (sent, total) {
          if (item._attempt != attempt || total <= 0) return;
          item.progress = (sent / total).clamp(0.0, 1.0);
          if (item.progress - lastShown >= 0.01 || item.progress >= 1) {
            lastShown = item.progress;
            _changed();
          }
        },
      );
      if (item._attempt != attempt) return;
      item
        ..storageId = id
        ..progress = 1
        ..state = ListingMediaState.uploaded;
    } catch (e) {
      if (item._attempt != attempt) return;
      item
        ..state = ListingMediaState.failed
        ..error = e is MediaUploadException ? e.message : 'Upload failed. Check your connection and try again.';
    }
    _changed();
  }
}

String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// Photos (reorderable, first = cover) and videos, each with live upload status.
class ListingMediaEditor extends StatelessWidget {
  final ListingMediaController controller;
  final ListingMediaSource source;

  const ListingMediaEditor({super.key, required this.controller, this.source = const DeviceListingMediaSource()});

  // Problems are shown inline (a snackbar would cover the step's action bar).
  Future<void> _addPhotos(BuildContext context) async {
    final remaining = kMaxListingPhotos - controller.photos.length;
    if (remaining <= 0) {
      controller.setNotice('A listing can have up to $kMaxListingPhotos photos.');
      return;
    }
    try {
      final files = await source.pickPhotos(context, max: remaining);
      if (files.isEmpty) return;
      controller.setNotice(await controller.addPhotos(files));
    } catch (_) {
      controller.setNotice('Could not open your photos. Check the app permissions.');
    }
  }

  Future<void> _addVideo(BuildContext context) async {
    if (controller.videos.length >= kMaxListingVideos) {
      controller.setNotice('A listing can have up to $kMaxListingVideos videos.');
      return;
    }
    try {
      final file = await source.pickVideo(context);
      if (file == null) return;
      controller.setNotice(await controller.addVideo(file));
    } catch (_) {
      controller.setNotice('Could not open your videos. Check the app permissions.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final photos = controller.photos;
        final videos = controller.videos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(
              icon: Icons.photo_library_outlined,
              title: 'Photos',
              count: '${photos.length}/$kMaxListingPhotos',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: Row(
                children: [
                  _AddTile(
                    key: const Key('media-add-photos'),
                    icon: Icons.add_a_photo_outlined,
                    label: 'Add photos',
                    onTap: () => _addPhotos(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: photos.isEmpty
                        ? const _EmptyHint(text: 'Add at least one photo.\nThe first one is the cover.')
                        : ReorderableListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            onReorder: controller.reorderPhotos,
                            itemBuilder: (context, i) => Padding(
                              key: ValueKey(photos[i].key),
                              padding: const EdgeInsets.only(right: 8),
                              child: _PhotoTile(
                                item: photos[i],
                                isCover: i == 0,
                                onRemove: () => controller.remove(photos[i]),
                                onRetry: () => controller.retry(photos[i]),
                                onMakeCover: i == 0 ? null : () => controller.makeCover(photos[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (photos.length > 1) ...[
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.pan_tool_alt_outlined, size: 14, color: AppColors.gray400),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text('Hold and drag to reorder',
                        style: TextStyle(fontSize: 11.5, color: AppColors.gray500, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _SectionLabel(
              icon: Icons.videocam_outlined,
              title: 'Videos',
              count: '${videos.length}/$kMaxListingVideos',
            ),
            const SizedBox(height: 8),
            for (final v in videos) ...[
              _VideoRow(
                item: v,
                client: controller.client,
                onRemove: () => controller.remove(v),
                onRetry: () => controller.retry(v),
              ),
              const SizedBox(height: 8),
            ],
            if (videos.length < kMaxListingVideos)
              _AddVideoButton(onTap: () => _addVideo(context)),
            if (controller.notice != null) ...[
              const SizedBox(height: 10),
              _Notice(text: controller.notice!, onClose: () => controller.setNotice(null)),
            ],
          ],
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _Notice({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('media-notice'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: AppColors.amberSurface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.amberDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.obsidian, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.gray500),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String count;
  const _SectionLabel({required this.icon, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.emeraldDark),
        const SizedBox(width: 6),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        ),
        Text(count, style: const TextStyle(fontSize: 12, color: AppColors.gray500, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.gray500, height: 1.35)),
    );
  }
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddTile({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Material(
        color: AppColors.emeraldSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.emerald.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.emeraldDark, size: 26),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final ListingMediaItem item;
  final bool isCover;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  final VoidCallback? onMakeCover;

  const _PhotoTile({
    required this.item,
    required this.isCover,
    required this.onRemove,
    required this.onRetry,
    required this.onMakeCover,
  });

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: InteractiveViewer(child: Image.memory(item.thumbnail!, fit: BoxFit.contain))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  if (onMakeCover != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onMakeCover!();
                      },
                      icon: const Icon(Icons.star_outline_rounded, size: 18),
                      label: const Text('Make cover'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.emeraldDark),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onRemove();
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.errorDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = item.state == ListingMediaState.failed;
    final uploading = item.state == ListingMediaState.uploading;
    return SizedBox(
      key: Key('media-${item.key}'),
      width: 104,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: failed ? onRetry : () => _preview(context),
              child: Image.memory(item.thumbnail!, fit: BoxFit.cover, cacheWidth: 320, gaplessPlayback: true),
            ),
            if (uploading)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          value: item.progress > 0 ? item.progress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${(item.progress * 100).round()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            if (failed)
              Material(
                color: AppColors.errorDark.withValues(alpha: 0.78),
                child: InkWell(
                  key: Key('media-retry-${item.key}'),
                  onTap: onRetry,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white),
                      SizedBox(height: 2),
                      Text('Failed · Retry', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            if (isCover)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  key: const Key('media-cover-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.emeraldDark, borderRadius: BorderRadius.circular(6)),
                  child: const Text('COVER', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                ),
              ),
            if (item.isUploaded)
              const Positioned(
                left: 6,
                bottom: 6,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: AppColors.emeraldDark,
                  child: Icon(Icons.check_rounded, size: 12, color: Colors.white),
                ),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: _RoundIcon(key: Key('media-remove-${item.key}'), icon: Icons.close_rounded, onTap: onRemove),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 14, color: AppColors.obsidian)),
      ),
    );
  }
}

class _VideoRow extends StatefulWidget {
  final ListingMediaItem item;
  final ConvexClientWrapper client;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  const _VideoRow({required this.item, required this.client, required this.onRemove, required this.onRetry});

  @override
  State<_VideoRow> createState() => _VideoRowState();
}

class _VideoRowState extends State<_VideoRow> {
  bool _opening = false;

  /// Plays the file exactly as it was stored (its Convex URL), not the local copy.
  Future<void> _preview() async {
    final id = widget.item.storageId;
    if (id == null) return;
    setState(() => _opening = true);
    final url = await MediaUploadService.fileUrl(widget.client, id);
    if (!mounted) return;
    setState(() => _opening = false);
    if (url == null) {
      agentSnack(context, 'The preview is not available right now.', error: true);
      return;
    }
    await VxVideoPlayerScreen.open(context, url, title: 'Video preview');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final failed = item.state == ListingMediaState.failed;
    final uploading = item.state == ListingMediaState.uploading;
    return AgentCard(
      key: Key('media-${item.key}'),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.obsidian, borderRadius: BorderRadius.circular(12)),
            child: Icon(failed ? Icons.videocam_off_outlined : Icons.play_circle_fill_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.file.name.isEmpty ? 'Video' : item.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                ),
                const SizedBox(height: 4),
                if (uploading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.progress > 0 ? item.progress : null,
                      minHeight: 5,
                      color: AppColors.emeraldDark,
                      backgroundColor: AppColors.gray100,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Uploading ${(item.progress * 100).round()}% · ${formatFileSize(item.bytes)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
                ] else if (failed)
                  Text(item.error ?? 'Upload failed',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.errorDark, fontWeight: FontWeight.w600))
                else
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.emeraldDark),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('Uploaded · ${formatFileSize(item.bytes)}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.emeraldDark, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (failed)
            IconButton(
              key: Key('media-retry-${item.key}'),
              tooltip: 'Retry upload',
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.emeraldDark),
            )
          else if (item.isUploaded)
            IconButton(
              key: Key('media-preview-${item.key}'),
              tooltip: 'Preview',
              onPressed: _opening ? null : _preview,
              icon: _opening
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.emeraldDark))
                  : const Icon(Icons.play_arrow_rounded, color: AppColors.emeraldDark),
            ),
          IconButton(
            key: Key('media-remove-${item.key}'),
            tooltip: 'Remove',
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.gray500),
          ),
        ],
      ),
    );
  }
}

class _AddVideoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddVideoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.gray50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      child: InkWell(
        key: const Key('media-add-video'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.video_call_outlined, color: AppColors.emeraldDark, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text('Add a video tour',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
              ),
              Text('≤ 1 min · 50 MB', style: TextStyle(fontSize: 11, color: AppColors.gray500, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
