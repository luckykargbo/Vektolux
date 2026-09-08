// lib/features/mobility/presentation/widgets/isometric_vehicle_3d_render.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — 3D Isometric Transparent Vehicle Render Engine
// High-resolution vector isometric illustrations with specular highlights,
// perspective shadows, glass reflections, and ambient underglow.
// Provides offline-safe 3D visuals for Keke, Okada, Sedan, and Cargo Van.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/vehicle_tier_catalog.dart';

/// Renders a transparent 3D isometric vehicle with optional network fallback
/// and high-fidelity CustomPainter vector art.
class IsometricVehicle3DRender extends StatelessWidget {
  final VehicleTierId tierId;
  final String? render3DUrl;
  final double width;
  final double height;
  final bool isSelected;
  final Color? customAccentColor;

  const IsometricVehicle3DRender({
    super.key,
    required this.tierId,
    this.render3DUrl,
    this.width = 80.0,
    this.height = 60.0,
    this.isSelected = false,
    this.customAccentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── 1. Ambient Isometric Ground Shadow & Selection Glow ──
          Positioned(
            bottom: 2,
            child: Container(
              width: width * 0.76,
              height: height * 0.22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.elliptical(width * 0.76, height * 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppColors.emerald.withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.16),
                    blurRadius: isSelected ? 12 : 6,
                    spreadRadius: isSelected ? 2 : 0,
                    offset: const Offset(2, 3),
                  ),
                ],
              ),
            ),
          ),

          // ── 2. Isometric 3D Vector Vehicle ──
          CustomPaint(
            size: Size(width, height),
            painter: _getPainter(tierId),
          ),
        ],
      ),
    );
  }

  CustomPainter _getPainter(VehicleTierId tier) {
    return switch (tier) {
      VehicleTierId.kekeBajaj => IsometricKekePainter(
          accentColor: customAccentColor ?? AppColors.amber,
          isSelected: isSelected,
        ),
      VehicleTierId.okadaBike => IsometricOkadaPainter(
          accentColor: customAccentColor ?? const Color(0xFFF97316),
          isSelected: isSelected,
        ),
      VehicleTierId.carStandard => IsometricSedanPainter(
          accentColor: customAccentColor ?? AppColors.emerald,
          isSelected: isSelected,
        ),
      VehicleTierId.deliveryVan => IsometricVanPainter(
          accentColor: customAccentColor ?? const Color(0xFF3B82F6),
          isSelected: isSelected,
        ),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════
//            1. ISOMETRIC 3D KEKE (BAJAJ TRICYCLE) PAINTER
// ═══════════════════════════════════════════════════════════════════════

class IsometricKekePainter extends CustomPainter {
  final Color accentColor;
  final bool isSelected;

  IsometricKekePainter({required this.accentColor, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Wheels & Tires (3D Angled Ellipses) ──
    final tirePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final rimPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    // Front wheel (front-left angled)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.25, h * 0.72), width: w * 0.14, height: h * 0.22),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.25, h * 0.72), width: w * 0.08, height: h * 0.13),
      rimPaint,
    );

    // Rear Right wheel
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.78, h * 0.62), width: w * 0.13, height: h * 0.20),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.78, h * 0.62), width: w * 0.07, height: h * 0.11),
      rimPaint,
    );

    // Rear Left wheel (partially visible)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.58, h * 0.76), width: w * 0.14, height: h * 0.22),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.58, h * 0.76), width: w * 0.08, height: h * 0.13),
      rimPaint,
    );

    // ── Lower Body / Chassis (Isometric Perspective) ──
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [accentColor, accentColor.withValues(alpha: 0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final bodyPath = Path();
    // Nose / mudguard
    bodyPath.moveTo(w * 0.20, h * 0.64);
    bodyPath.lineTo(w * 0.35, h * 0.52);
    // Cowl line
    bodyPath.lineTo(w * 0.50, h * 0.56);
    // Cabin side
    bodyPath.lineTo(w * 0.84, h * 0.44);
    bodyPath.lineTo(w * 0.86, h * 0.58);
    // Rear bottom
    bodyPath.lineTo(w * 0.58, h * 0.72);
    bodyPath.lineTo(w * 0.22, h * 0.70);
    bodyPath.close();
    canvas.drawPath(bodyPath, bodyPaint);

    // ── Upper Canopy / Roof (Dark Vinyl/Fiberglass) ──
    final roofPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF334155), Color(0xFF0F172A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final roofPath = Path();
    roofPath.moveTo(w * 0.32, h * 0.28);
    roofPath.lineTo(w * 0.54, h * 0.22);
    roofPath.lineTo(w * 0.84, h * 0.32);
    roofPath.lineTo(w * 0.60, h * 0.42);
    roofPath.close();
    canvas.drawPath(roofPath, roofPaint);

    // ── Cabin Pillars / Struts ──
    final strutPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    // Front strut
    canvas.drawLine(Offset(w * 0.35, h * 0.52), Offset(w * 0.36, h * 0.30), strutPaint);
    // Middle strut
    canvas.drawLine(Offset(w * 0.52, h * 0.56), Offset(w * 0.58, h * 0.40), strutPaint);
    // Rear strut
    canvas.drawLine(Offset(w * 0.84, h * 0.48), Offset(w * 0.82, h * 0.33), strutPaint);

    // ── Windshield (Angled Glass with Glare Reflection) ──
    final glassPath = Path();
    glassPath.moveTo(w * 0.34, h * 0.32);
    glassPath.lineTo(w * 0.52, h * 0.26);
    glassPath.lineTo(w * 0.48, h * 0.48);
    glassPath.lineTo(w * 0.35, h * 0.50);
    glassPath.close();

    final glassPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(glassPath, glassPaint);

    // Windshield Glare Line
    final glarePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.38, h * 0.46), Offset(w * 0.48, h * 0.30), glarePaint);

    // ── Front Headlight (Bright Xenon Beam) ──
    final lightPaint = Paint()..color = const Color(0xFFFEF08A);
    canvas.drawCircle(Offset(w * 0.19, h * 0.64), 3.0, lightPaint);
  }

  @override
  bool shouldRepaint(covariant IsometricKekePainter old) =>
      old.accentColor != accentColor || old.isSelected != isSelected;
}

// ═══════════════════════════════════════════════════════════════════════
//            2. ISOMETRIC 3D OKADA (MOTORBIKE) PAINTER
// ═══════════════════════════════════════════════════════════════════════

class IsometricOkadaPainter extends CustomPainter {
  final Color accentColor;
  final bool isSelected;

  IsometricOkadaPainter({required this.accentColor, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final tirePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final rimPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;

    // ── Wheels (Angled Spokes) ──
    // Front Wheel
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.22, h * 0.68), width: w * 0.13, height: h * 0.24),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.22, h * 0.68), width: w * 0.07, height: h * 0.14),
      rimPaint,
    );

    // Rear Wheel
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.76, h * 0.60), width: w * 0.14, height: h * 0.25),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.76, h * 0.60), width: w * 0.08, height: h * 0.15),
      rimPaint,
    );

    // ── Front Fork Suspension ──
    final forkPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.22, h * 0.68), Offset(w * 0.32, h * 0.36), forkPaint);

    // ── Handlebars & Grips ──
    final barPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.26, h * 0.33), Offset(w * 0.39, h * 0.38), barPaint);

    // ── Engine Block & Exhaust ──
    final enginePaint = Paint()..color = const Color(0xFF475569);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, h * 0.54, w * 0.18, h * 0.18),
        const Radius.circular(3),
      ),
      enginePaint,
    );
    // Exhaust Pipe (Chrome)
    final chromePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.46, h * 0.66), Offset(w * 0.82, h * 0.58), chromePaint);

    // ── Sculpted Fuel Tank (Vibrant Body Paint) ──
    final tankPath = Path();
    tankPath.moveTo(w * 0.32, h * 0.38);
    tankPath.lineTo(w * 0.48, h * 0.35);
    tankPath.lineTo(w * 0.54, h * 0.48);
    tankPath.lineTo(w * 0.36, h * 0.52);
    tankPath.close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [accentColor, accentColor.withValues(alpha: 0.8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(tankPath, bodyPaint);

    // ── Seat (Ergonomic Leather Saddle) ──
    final seatPath = Path();
    seatPath.moveTo(w * 0.48, h * 0.42);
    seatPath.lineTo(w * 0.72, h * 0.38);
    seatPath.lineTo(w * 0.70, h * 0.48);
    seatPath.lineTo(w * 0.52, h * 0.50);
    seatPath.close();

    final seatPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawPath(seatPath, seatPaint);

    // ── Headlight ──
    canvas.drawCircle(Offset(w * 0.20, h * 0.42), 3.0, Paint()..color = const Color(0xFFFEF08A));
  }

  @override
  bool shouldRepaint(covariant IsometricOkadaPainter old) =>
      old.accentColor != accentColor || old.isSelected != isSelected;
}

// ═══════════════════════════════════════════════════════════════════════
//            3. ISOMETRIC 3D SEDAN (TAXI / STANDARD RIDE) PAINTER
// ═══════════════════════════════════════════════════════════════════════

class IsometricSedanPainter extends CustomPainter {
  final Color accentColor;
  final bool isSelected;

  IsometricSedanPainter({required this.accentColor, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final tirePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final rimPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    // ── 4 Isometric Wheels ──
    // Front Right (tucked under)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.38, h * 0.56), width: w * 0.08, height: h * 0.14),
      tirePaint,
    );
    // Front Left (prominent)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.24, h * 0.72), width: w * 0.12, height: h * 0.22),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.24, h * 0.72), width: w * 0.07, height: h * 0.13),
      rimPaint,
    );
    // Rear Left
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.74, h * 0.65), width: w * 0.12, height: h * 0.22),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.74, h * 0.65), width: w * 0.07, height: h * 0.13),
      rimPaint,
    );

    // ── Aerodynamic Sedan Body ──
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [accentColor, accentColor.withValues(alpha: 0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final bodyPath = Path();
    // Front nose
    bodyPath.moveTo(w * 0.10, h * 0.62);
    // Hood slant
    bodyPath.lineTo(w * 0.28, h * 0.46);
    // Windshield frame
    bodyPath.lineTo(w * 0.44, h * 0.30);
    // Roofline
    bodyPath.lineTo(w * 0.68, h * 0.33);
    // Rear windscreen & boot
    bodyPath.lineTo(w * 0.82, h * 0.46);
    bodyPath.lineTo(w * 0.92, h * 0.52);
    // Rear bumper
    bodyPath.lineTo(w * 0.88, h * 0.62);
    // Undercarriage to front
    bodyPath.lineTo(w * 0.16, h * 0.74);
    bodyPath.close();
    canvas.drawPath(bodyPath, bodyPaint);

    // ── Glass Greenhouse (Windshield & Windows) ──
    final glassPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    // Front windshield
    final frontGlass = Path();
    frontGlass.moveTo(w * 0.30, h * 0.46);
    frontGlass.lineTo(w * 0.44, h * 0.32);
    frontGlass.lineTo(w * 0.52, h * 0.34);
    frontGlass.lineTo(w * 0.40, h * 0.49);
    frontGlass.close();
    canvas.drawPath(frontGlass, glassPaint);

    // Side windows
    final sideGlass = Path();
    sideGlass.moveTo(w * 0.42, h * 0.49);
    sideGlass.lineTo(w * 0.54, h * 0.35);
    sideGlass.lineTo(w * 0.66, h * 0.36);
    sideGlass.lineTo(w * 0.68, h * 0.48);
    sideGlass.close();
    canvas.drawPath(sideGlass, glassPaint);

    // Specular Window Glare
    final glarePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.34, h * 0.46), Offset(w * 0.48, h * 0.33), glarePaint);

    // ── Headlights & Taillights ──
    // Front Headlight (Warm yellow xenon)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.12, h * 0.60), width: w * 0.05, height: h * 0.07),
      Paint()..color = const Color(0xFFFEF08A),
    );
    // Rear Taillight (Red LED)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.90, h * 0.54), width: w * 0.04, height: h * 0.06),
      Paint()..color = const Color(0xFFEF4444),
    );
  }

  @override
  bool shouldRepaint(covariant IsometricSedanPainter old) =>
      old.accentColor != accentColor || old.isSelected != isSelected;
}

// ═══════════════════════════════════════════════════════════════════════
//            4. ISOMETRIC 3D CARGO / DELIVERY VAN PAINTER
// ═══════════════════════════════════════════════════════════════════════

class IsometricVanPainter extends CustomPainter {
  final Color accentColor;
  final bool isSelected;

  IsometricVanPainter({required this.accentColor, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final tirePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final rimPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    // ── Wheels ──
    // Front Left
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.24, h * 0.74), width: w * 0.12, height: h * 0.22),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.24, h * 0.74), width: w * 0.07, height: h * 0.13),
      rimPaint,
    );
    // Rear Left
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.74, h * 0.66), width: w * 0.13, height: h * 0.23),
      tirePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.74, h * 0.66), width: w * 0.07, height: h * 0.13),
      rimPaint,
    );

    // ── High-Roof Commercial Cargo Body ──
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [accentColor, accentColor.withValues(alpha: 0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final vanPath = Path();
    // Front bumper
    vanPath.moveTo(w * 0.10, h * 0.66);
    // Front cab nose
    vanPath.lineTo(w * 0.14, h * 0.54);
    // Windshield rake
    vanPath.lineTo(w * 0.28, h * 0.32);
    // High cargo roofline
    vanPath.lineTo(w * 0.84, h * 0.24);
    // Vertical rear cargo doors
    vanPath.lineTo(w * 0.90, h * 0.52);
    vanPath.lineTo(w * 0.86, h * 0.64);
    // Lower sill
    vanPath.lineTo(w * 0.16, h * 0.76);
    vanPath.close();
    canvas.drawPath(vanPath, bodyPaint);

    // ── Cab Windshield & Side Window ──
    final glassPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    // Windshield
    final cabGlass = Path();
    cabGlass.moveTo(w * 0.16, h * 0.52);
    cabGlass.lineTo(w * 0.28, h * 0.34);
    cabGlass.lineTo(w * 0.38, h * 0.37);
    cabGlass.lineTo(w * 0.26, h * 0.56);
    cabGlass.close();
    canvas.drawPath(cabGlass, glassPaint);

    // Driver side door window
    final sideGlass = Path();
    sideGlass.moveTo(w * 0.28, h * 0.56);
    sideGlass.lineTo(w * 0.39, h * 0.38);
    sideGlass.lineTo(w * 0.48, h * 0.40);
    sideGlass.lineTo(w * 0.44, h * 0.57);
    sideGlass.close();
    canvas.drawPath(sideGlass, glassPaint);

    // Cargo Door Seam (Vertical Panel Division)
    final seamPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.48, h * 0.41), Offset(w * 0.48, h * 0.70), seamPaint);
    // Sliding door track
    canvas.drawLine(Offset(w * 0.48, h * 0.55), Offset(w * 0.82, h * 0.50), seamPaint);

    // Front Headlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.10, h * 0.58, w * 0.05, h * 0.08),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFEF08A),
    );
  }

  @override
  bool shouldRepaint(covariant IsometricVanPainter old) =>
      old.accentColor != accentColor || old.isSelected != isSelected;
}
