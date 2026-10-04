// lib/core/widgets/vx_video_player.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Full-screen player for a listing video (a real uploaded file URL).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

class VxVideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  const VxVideoPlayerScreen({super.key, required this.url, this.title = 'Property video'});

  static Future<void> open(BuildContext context, String url, {String title = 'Property video'}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VxVideoPlayerScreen(url: url, title: title)));

  @override
  State<VxVideoPlayerScreen> createState() => _VxVideoPlayerScreenState();
}

class _VxVideoPlayerScreenState extends State<VxVideoPlayerScreen> {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _failed
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
                          SizedBox(height: 10),
                          Text('This video could not be played.', style: TextStyle(color: Colors.white70)),
                        ],
                      )
                    : value.isInitialized
                        ? GestureDetector(
                            onTap: () => value.isPlaying ? _controller.pause() : _controller.play(),
                            child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(_controller)),
                          )
                        : const CircularProgressIndicator(color: AppColors.emerald),
              ),
            ),
            if (value.isInitialized && !_failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      onPressed: () => value.isPlaying ? _controller.pause() : _controller.play(),
                      icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 30),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(playedColor: AppColors.emerald, bufferedColor: Colors.white24, backgroundColor: Colors.white12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${_clock(value.position)} / ${_clock(value.duration)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
