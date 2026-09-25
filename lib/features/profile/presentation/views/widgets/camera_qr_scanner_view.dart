import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../../core/theme/app_colors.dart';

/// Full-screen live camera QR scanner with animated viewfinder overlay
/// and haptic feedback on detecting Vektolux user/payment QR codes.
class CameraQrScannerView extends StatefulWidget {
  const CameraQrScannerView({super.key});

  /// Static helper to launch the scanner and return the scanned QR payload string
  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CameraQrScannerView(),
      ),
    );
  }

  @override
  State<CameraQrScannerView> createState() => _CameraQrScannerViewState();
}

class _CameraQrScannerViewState extends State<CameraQrScannerView> {
  late final MobileScannerController _controller;
  bool _hasDetected = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() => _hasDetected = true);
        HapticFeedback.mediumImpact();
        _controller.stop();
        Navigator.of(context).pop(rawValue);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanBoxSize = size.width * 0.72;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Live Camera Stream
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Custom Viewfinder Dark Overlay with Center Cutout
          CustomPaint(
            size: size,
            painter: _ScannerOverlayPainter(
              boxSize: scanBoxSize,
              borderColor: AppColors.emerald,
            ),
          ),

          // Top Header & Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 20,
                        child: IconButton(
                          icon: Icon(
                            _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: _isTorchOn ? AppColors.emerald : Colors.white,
                            size: 20,
                          ),
                          onPressed: () async {
                            await _controller.toggleTorch();
                            setState(() => _isTorchOn = !_isTorchOn);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 20,
                        child: IconButton(
                          icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
                          onPressed: () => _controller.switchCamera(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Prompt Instruction Card & Manual Input Option
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: AppColors.emerald, size: 26),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Scan Vektolux Account QR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Align Vektolux Account QR within frame to transfer funds instantly',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text(
                    'Enter Recipient Manually',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () {
                    _controller.stop();
                    Navigator.of(context).pop('__MANUAL__');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the semi-transparent black overlay and glowing green corner brackets
class _ScannerOverlayPainter extends CustomPainter {
  final double boxSize;
  final Color borderColor;

  _ScannerOverlayPainter({
    required this.boxSize,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.black.withValues(alpha: 0.62);

    final centerX = size.width / 2;
    final centerY = size.height * 0.44;

    final left = centerX - (boxSize / 2);
    final top = centerY - (boxSize / 2);
    final scanRect = Rect.fromLTWH(left, top, boxSize, boxSize);
    final scanRRect = RRect.fromRectAndRadius(scanRect, const Radius.circular(20));

    // Draw background with transparent cutout window
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(scanRRect);
    final overlayPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    canvas.drawPath(overlayPath, backgroundPaint);

    // Draw stylized corner brackets
    final cornerPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 20.0;

    // Top-Left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLen)
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top), radius: const Radius.circular(r))
        ..lineTo(left + cornerLen, top),
      cornerPaint,
    );

    // Top-Right
    canvas.drawPath(
      Path()
        ..moveTo(left + boxSize - cornerLen, top)
        ..lineTo(left + boxSize - r, top)
        ..arcToPoint(Offset(left + boxSize, top + r), radius: const Radius.circular(r))
        ..lineTo(left + boxSize, top + cornerLen),
      cornerPaint,
    );

    // Bottom-Left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + boxSize - cornerLen)
        ..lineTo(left, top + boxSize - r)
        ..arcToPoint(Offset(left + r, top + boxSize), radius: const Radius.circular(r))
        ..lineTo(left + cornerLen, top + boxSize),
      cornerPaint,
    );

    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(left + boxSize - cornerLen, top + boxSize)
        ..lineTo(left + boxSize - r, top + boxSize)
        ..arcToPoint(Offset(left + boxSize, top + boxSize - r), radius: const Radius.circular(r))
        ..lineTo(left + boxSize, top + boxSize - cornerLen),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) => false;
}
