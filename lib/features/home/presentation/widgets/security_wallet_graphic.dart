// lib/features/home/presentation/widgets/security_wallet_graphic.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Premium 3D Security Wallet Graphic
// High-fidelity emerald escrow wallet with periodic 10-second subtle
// security verification pulse & luminous emerald sparks.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class SecurityWalletGraphic extends StatefulWidget {
  final double width;
  final double height;

  const SecurityWalletGraphic({
    super.key,
    this.width = 114,
    this.height = 96,
  });

  @override
  State<SecurityWalletGraphic> createState() => _SecurityWalletGraphicState();
}

class _SecurityWalletGraphicState extends State<SecurityWalletGraphic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Timer? _intervalTimer;

  // Particle sparkle offsets relative to normalized box [-1, 1]
  static const List<_SparkleOffset> _sparkles = [
    _SparkleOffset(dx: -0.32, dy: 0.12, size: 5.5, delay: 0.1), // Near shield
    _SparkleOffset(dx: -0.68, dy: 0.28, size: 4.0, delay: 0.2), // Left edge
    _SparkleOffset(dx: 0.42, dy: 0.22, size: 4.5, delay: 0.15), // Near strap button
    _SparkleOffset(dx: -0.10, dy: -0.42, size: 5.0, delay: 0.25), // Above banknotes
    _SparkleOffset(dx: 0.65, dy: 0.48, size: 3.5, delay: 0.3),  // Bottom right rim
    _SparkleOffset(dx: 0.15, dy: 0.62, size: 4.0, delay: 0.2),  // Bottom stitch
  ];

  @override
  void initState() {
    super.initState();
    // 1.3 second pulse duration
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    // Trigger security spark every 10 seconds
    _startPulseTimer();
  }

  void _startPulseTimer() {
    _intervalTimer?.cancel();
    _intervalTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _pulseController.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _intervalTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final t = _pulseController.value;
          // Sine curve for smooth in-and-out: 0 -> 1 -> 0
          final pulseIntensity = math.sin(t * math.pi);

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // 1. Subtle Ambient Emerald Glow Behind Wallet
              if (pulseIntensity > 0.01)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: widget.width * 0.85,
                      height: widget.height * 0.75,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.30 * pulseIntensity),
                            blurRadius: 18 * pulseIntensity,
                            spreadRadius: 4 * pulseIntensity,
                          ),
                          BoxShadow(
                            color: const Color(0xFF34D399)
                                .withValues(alpha: 0.18 * pulseIntensity),
                            blurRadius: 28 * pulseIntensity,
                            spreadRadius: 8 * pulseIntensity,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 2. The 3D Green Security Wallet Asset
              Transform.scale(
                // Microscopic breath during pulse (1.0 -> 1.012 -> 1.0), rock solid stability
                scale: 1.0 + (0.012 * pulseIntensity),
                child: Image.asset(
                  'assets/images/wallet/green_security_wallet.png',
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),

              // 3. Shield Center Soft Brightening Overlay
              if (pulseIntensity > 0.01)
                Positioned(
                  left: widget.width * 0.28,
                  top: widget.height * 0.42,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.35 * pulseIntensity),
                          const Color(0xFF34D399)
                              .withValues(alpha: 0.25 * pulseIntensity),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),

              // 4. Luminous Emerald Security Sparks / Particles
              if (pulseIntensity > 0.01)
                ..._sparkles.map((sp) {
                  // Phase delay calculation for each particle
                  final localT = (t - sp.delay).clamp(0.0, 1.0);
                  final localIntensity = math.sin(localT * math.pi);
                  if (localIntensity <= 0.01) return const SizedBox.shrink();

                  final posX = (widget.width / 2) +
                      (sp.dx * (widget.width / 2)) -
                      (sp.size / 2);
                  final posY = (widget.height / 2) +
                      (sp.dy * (widget.height / 2)) -
                      (sp.size / 2);

                  return Positioned(
                    left: posX,
                    top: posY,
                    child: Opacity(
                      opacity: (localIntensity * 0.95).clamp(0.0, 1.0),
                      child: Container(
                        width: sp.size,
                        height: sp.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE6FFFA),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.8),
                              blurRadius: 4,
                              spreadRadius: 1.5,
                            ),
                            BoxShadow(
                              color: const Color(0xFF34D399)
                                  .withValues(alpha: 0.5),
                              blurRadius: 7,
                              spreadRadius: 2.5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _SparkleOffset {
  final double dx;
  final double dy;
  final double size;
  final double delay;

  const _SparkleOffset({
    required this.dx,
    required this.dy,
    required this.size,
    required this.delay,
  });
}
