// lib/features/mobility/presentation/widgets/top_down_vehicle_painter.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Uber-Style Top-Down Vector Vehicle Markers
// Lightweight, crisp vector silhouettes rendered via CustomPainter.
// Supports Kekeh (3-wheel tricycle), Okada (2-wheel bike), and Taxi/Sedan.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Vehicle silhouette types supported on the Vektolux live map.
enum VehicleSilhouetteType {
  keke,
  okada,
  car,
  van,
}

/// Helper to determine silhouette type from a string category.
VehicleSilhouetteType getVehicleSilhouette(String? category) {
  final cat = (category ?? '').toLowerCase();
  if (cat.contains('van') || cat.contains('cargo') || cat.contains('truck') || cat.contains('delivery_van') || cat.contains('haulage')) {
    return VehicleSilhouetteType.van;
  }
  if (cat.contains('keke') || cat.contains('tricycle') || cat.contains('bajaj')) {
    return VehicleSilhouetteType.keke;
  }
  if (cat.contains('bike') || cat.contains('okada') || cat.contains('courier') || cat.contains('delivery')) {
    return VehicleSilhouetteType.okada;
  }
  return VehicleSilhouetteType.car;
}

/// Widget rendering a top-down vector vehicle silhouette.
class TopDownVehicleWidget extends StatelessWidget {
  final String? category;
  final double size;
  final Color? accentColor;

  const TopDownVehicleWidget({
    super.key,
    this.category,
    this.size = 38.0,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final type = getVehicleSilhouette(category);

    CustomPainter painter;
    switch (type) {
      case VehicleSilhouetteType.keke:
        painter = KekeTopDownPainter(accentColor: accentColor ?? AppColors.amber);
        break;
      case VehicleSilhouetteType.okada:
        painter = OkadaTopDownPainter(accentColor: accentColor ?? const Color(0xFFF97316));
        break;
      case VehicleSilhouetteType.car:
        painter = SedanTopDownPainter(accentColor: accentColor ?? AppColors.emerald);
        break;
      case VehicleSilhouetteType.van:
        painter = VanTopDownPainter(accentColor: accentColor ?? const Color(0xFF3B82F6));
        break;
    }

    return CustomPaint(
      size: Size(size, size),
      painter: painter,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//               1. KEKE (3-WHEEL TRICYCLE) VECTOR PAINTER
// ═══════════════════════════════════════════════════════════════════════

class KekeTopDownPainter extends CustomPainter {
  final Color accentColor;

  KekeTopDownPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Center offset
    canvas.save();

    final wheelPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final bodyPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final roofPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final windshieldPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;

    final headlightPaint = Paint()
      ..color = const Color(0xFFFEF08A)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // ── 1. Wheels ──
    // Front Wheel (single top-center)
    final frontWheelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.16), width: w * 0.12, height: h * 0.22),
      const Radius.circular(2),
    );
    canvas.drawRRect(frontWheelRect, wheelPaint);

    // Rear Left Wheel
    final rearLeftWheel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.18, h * 0.74), width: w * 0.11, height: h * 0.22),
      const Radius.circular(2),
    );
    canvas.drawRRect(rearLeftWheel, wheelPaint);

    // Rear Right Wheel
    final rearRightWheel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.82, h * 0.74), width: w * 0.11, height: h * 0.22),
      const Radius.circular(2),
    );
    canvas.drawRRect(rearRightWheel, wheelPaint);

    // ── 2. Triangular Front Cowl / Body ──
    final bodyPath = Path();
    bodyPath.moveTo(w * 0.5, h * 0.20); // nose point
    bodyPath.lineTo(w * 0.74, h * 0.42); // right shoulder
    bodyPath.lineTo(w * 0.76, h * 0.86); // rear right
    bodyPath.lineTo(w * 0.24, h * 0.86); // rear left
    bodyPath.lineTo(w * 0.26, h * 0.42); // left shoulder
    bodyPath.close();

    canvas.drawPath(bodyPath, bodyPaint);
    canvas.drawPath(bodyPath, borderPaint);

    // ── 3. Front Windshield Arc ──
    final windshieldPath = Path();
    windshieldPath.moveTo(w * 0.34, h * 0.44);
    windshieldPath.quadraticBezierTo(w * 0.5, h * 0.35, w * 0.66, h * 0.44);
    windshieldPath.lineTo(w * 0.64, h * 0.49);
    windshieldPath.quadraticBezierTo(w * 0.5, h * 0.42, w * 0.36, h * 0.49);
    windshieldPath.close();
    canvas.drawPath(windshieldPath, windshieldPaint);

    // ── 4. Main Cabin Roof Panel ──
    final cabinRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.30, h * 0.50, w * 0.40, h * 0.32),
      const Radius.circular(3),
    );
    canvas.drawRRect(cabinRect, roofPaint);

    // ── 5. Headlight Dot ──
    canvas.drawCircle(Offset(w * 0.5, h * 0.21), w * 0.04, headlightPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KekeTopDownPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

// ═══════════════════════════════════════════════════════════════════════
//               2. OKADA (2-WHEEL MOTORBIKE) VECTOR PAINTER
// ═══════════════════════════════════════════════════════════════════════

class OkadaTopDownPainter extends CustomPainter {
  final Color accentColor;

  OkadaTopDownPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();

    final wheelPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final bodyPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final handlebarPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final seatPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final headlightPaint = Paint()
      ..color = const Color(0xFFFEF08A)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // ── 1. Front Wheel ──
    final frontWheel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.16), width: w * 0.10, height: h * 0.26),
      const Radius.circular(2),
    );
    canvas.drawRRect(frontWheel, wheelPaint);

    // ── 2. Handlebars ──
    canvas.drawLine(Offset(w * 0.26, h * 0.32), Offset(w * 0.74, h * 0.32), handlebarPaint);
    // Grip ends
    canvas.drawCircle(Offset(w * 0.26, h * 0.32), 2.0, wheelPaint);
    canvas.drawCircle(Offset(w * 0.74, h * 0.32), 2.0, wheelPaint);

    // ── 3. Rear Wheel ──
    final rearWheel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.82), width: w * 0.11, height: h * 0.28),
      const Radius.circular(2),
    );
    canvas.drawRRect(rearWheel, wheelPaint);

    // ── 4. Main Body / Fuel Tank (Teardrop shape) ──
    final tankPath = Path();
    tankPath.moveTo(w * 0.5, h * 0.28);
    tankPath.quadraticBezierTo(w * 0.65, h * 0.36, w * 0.62, h * 0.52);
    tankPath.quadraticBezierTo(w * 0.5, h * 0.56, w * 0.38, h * 0.52);
    tankPath.quadraticBezierTo(w * 0.35, h * 0.36, w * 0.5, h * 0.28);
    tankPath.close();
    canvas.drawPath(tankPath, bodyPaint);
    canvas.drawPath(tankPath, borderPaint);

    // ── 5. Rider Saddle / Seat ──
    final seatRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.64), width: w * 0.22, height: h * 0.24),
      const Radius.circular(3),
    );
    canvas.drawRRect(seatRect, seatPaint);

    // ── 6. Headlight ──
    canvas.drawCircle(Offset(w * 0.5, h * 0.16), w * 0.04, headlightPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OkadaTopDownPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

// ═══════════════════════════════════════════════════════════════════════
//               3. CAR / TAXI (SEDAN) VECTOR PAINTER
// ═══════════════════════════════════════════════════════════════════════

class SedanTopDownPainter extends CustomPainter {
  final Color accentColor;

  SedanTopDownPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();

    final wheelPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final bodyPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final glassPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.fill;

    final roofPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final headlightPaint = Paint()
      ..color = const Color(0xFFFEF08A)
      ..style = PaintingStyle.fill;

    final tailLightPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    // ── 1. 4 Wheels tucked in sides ──
    // Front Left
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.18, h * 0.28), width: w * 0.09, height: h * 0.18),
        const Radius.circular(2),
      ),
      wheelPaint,
    );
    // Front Right
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.82, h * 0.28), width: w * 0.09, height: h * 0.18),
        const Radius.circular(2),
      ),
      wheelPaint,
    );
    // Rear Left
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.18, h * 0.72), width: w * 0.09, height: h * 0.18),
        const Radius.circular(2),
      ),
      wheelPaint,
    );
    // Rear Right
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.82, h * 0.72), width: w * 0.09, height: h * 0.18),
        const Radius.circular(2),
      ),
      wheelPaint,
    );

    // ── 2. Aerodynamic Sedan Body ──
    final carPath = Path();
    // Rounded nose
    carPath.moveTo(w * 0.38, h * 0.12);
    carPath.quadraticBezierTo(w * 0.5, h * 0.09, w * 0.62, h * 0.12);
    // Right hood & front wheel arch flare
    carPath.lineTo(w * 0.75, h * 0.20);
    carPath.quadraticBezierTo(w * 0.78, h * 0.32, w * 0.76, h * 0.44);
    // Right waistline & rear flare
    carPath.lineTo(w * 0.77, h * 0.68);
    carPath.quadraticBezierTo(w * 0.78, h * 0.82, w * 0.72, h * 0.88);
    // Rear bumper
    carPath.quadraticBezierTo(w * 0.5, h * 0.90, w * 0.28, h * 0.88);
    // Left waistline & front flare
    carPath.quadraticBezierTo(w * 0.22, h * 0.82, w * 0.23, h * 0.68);
    carPath.lineTo(w * 0.24, h * 0.44);
    carPath.quadraticBezierTo(w * 0.22, h * 0.32, w * 0.25, h * 0.20);
    carPath.close();

    canvas.drawPath(carPath, bodyPaint);
    canvas.drawPath(carPath, borderPaint);

    // ── 3. Front Windshield (curved arc) ──
    final frontWindshield = Path();
    frontWindshield.moveTo(w * 0.32, h * 0.36);
    frontWindshield.quadraticBezierTo(w * 0.5, h * 0.30, w * 0.68, h * 0.36);
    frontWindshield.lineTo(w * 0.65, h * 0.42);
    frontWindshield.quadraticBezierTo(w * 0.5, h * 0.37, w * 0.35, h * 0.42);
    frontWindshield.close();
    canvas.drawPath(frontWindshield, glassPaint);

    // ── 4. Main Roof Panel ──
    final roofRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.32, h * 0.43, w * 0.36, h * 0.25),
      const Radius.circular(3),
    );
    canvas.drawRRect(roofRect, roofPaint);

    // ── 5. Rear Windshield ──
    final rearWindshield = Path();
    rearWindshield.moveTo(w * 0.35, h * 0.69);
    rearWindshield.quadraticBezierTo(w * 0.5, h * 0.72, w * 0.65, h * 0.69);
    rearWindshield.lineTo(w * 0.67, h * 0.75);
    rearWindshield.quadraticBezierTo(w * 0.5, h * 0.78, w * 0.33, h * 0.75);
    rearWindshield.close();
    canvas.drawPath(rearWindshield, glassPaint);

    // ── 6. Front Headlights ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.33, h * 0.14), width: w * 0.08, height: h * 0.04),
        const Radius.circular(1),
      ),
      headlightPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.67, h * 0.14), width: w * 0.08, height: h * 0.04),
        const Radius.circular(1),
      ),
      headlightPaint,
    );

    // ── 7. Rear Tail Lights ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.32, h * 0.88), width: w * 0.08, height: h * 0.03),
        const Radius.circular(1),
      ),
      tailLightPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.68, h * 0.88), width: w * 0.08, height: h * 0.03),
        const Radius.circular(1),
      ),
      tailLightPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SedanTopDownPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

// ═══════════════════════════════════════════════════════════════════════
//               4. DELIVERY VAN / CARGO TRUCK VECTOR PAINTER
// ═══════════════════════════════════════════════════════════════════════

class VanTopDownPainter extends CustomPainter {
  final Color accentColor;

  VanTopDownPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();

    final wheelPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final bodyPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    final glassPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.fill;

    final roofPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final ribPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final headlightPaint = Paint()
      ..color = const Color(0xFFFEF08A)
      ..style = PaintingStyle.fill;

    final tailLightPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    // ── 1. 4 Sturdy Wheels ──
    // Front Left
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.16, h * 0.28), width: w * 0.09, height: h * 0.20),
        const Radius.circular(2),
      ),
      wheelPaint,
    );
    // Front Right
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.84, h * 0.28), width: w * 0.09, height: h * 0.20),
        const Radius.circular(2),
      ),
      wheelPaint,
    );
    // Rear Left
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.16, h * 0.74), width: w * 0.10, height: h * 0.22),
        const Radius.circular(2),
      ),
      wheelPaint,
    );
    // Rear Right
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.84, h * 0.74), width: w * 0.10, height: h * 0.22),
        const Radius.circular(2),
      ),
      wheelPaint,
    );

    // ── 2. Boxy Commercial Van Body ──
    final vanRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.20, h * 0.12, w * 0.60, h * 0.78),
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(8),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(vanRect, bodyPaint);
    canvas.drawRRect(vanRect, borderPaint);

    // ── 3. Front Cab Windshield ──
    final windshieldPath = Path();
    windshieldPath.moveTo(w * 0.26, h * 0.26);
    windshieldPath.quadraticBezierTo(w * 0.50, h * 0.22, w * 0.74, h * 0.26);
    windshieldPath.lineTo(w * 0.72, h * 0.34);
    windshieldPath.lineTo(w * 0.28, h * 0.34);
    windshieldPath.close();
    canvas.drawPath(windshieldPath, glassPaint);

    // ── 4. Main Cargo Roof Panel ──
    final cargoRoof = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.24, h * 0.38, w * 0.52, h * 0.48),
      const Radius.circular(3),
    );
    canvas.drawRRect(cargoRoof, roofPaint);

    // Longitudinal Roof Ribs (3 Ridges for cargo reinforcement)
    canvas.drawLine(Offset(w * 0.34, h * 0.40), Offset(w * 0.34, h * 0.83), ribPaint);
    canvas.drawLine(Offset(w * 0.50, h * 0.40), Offset(w * 0.50, h * 0.83), ribPaint);
    canvas.drawLine(Offset(w * 0.66, h * 0.40), Offset(w * 0.66, h * 0.83), ribPaint);

    // ── 5. Rear Split Door Seam ──
    final seamPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.50, h * 0.86), Offset(w * 0.50, h * 0.90), seamPaint);

    // ── 6. Front Headlights ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.29, h * 0.14), width: w * 0.08, height: h * 0.035),
        const Radius.circular(1),
      ),
      headlightPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.71, h * 0.14), width: w * 0.08, height: h * 0.035),
        const Radius.circular(1),
      ),
      headlightPaint,
    );

    // ── 7. Rear Taillights ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.25, h * 0.89), width: w * 0.06, height: h * 0.03),
        const Radius.circular(1),
      ),
      tailLightPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.75, h * 0.89), width: w * 0.06, height: h * 0.03),
        const Radius.circular(1),
      ),
      tailLightPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VanTopDownPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

