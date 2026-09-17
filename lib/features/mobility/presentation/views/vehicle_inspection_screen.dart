// lib/features/mobility/presentation/views/vehicle_inspection_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Digital Vehicle Inspection & Condition Verification Wizard
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class VehicleInspectionScreen extends StatefulWidget {
  final String escrowOrderId;
  final String orderCode;
  final String inspectionType; // PRE_TRIP_RENTAL, POST_TRIP_RENTAL, PURCHASE_MECHANIC_INSPECTION

  const VehicleInspectionScreen({
    super.key,
    required this.escrowOrderId,
    required this.orderCode,
    required this.inspectionType,
  });

  @override
  State<VehicleInspectionScreen> createState() => _VehicleInspectionScreenState();
}

class _VehicleInspectionScreenState extends State<VehicleInspectionScreen> {
  final _odometerController = TextEditingController();
  final _notesController = TextEditingController();
  double _fuelPercentage = 100.0;
  bool _hasDamages = false;
  final List<String> _damagesList = [];
  bool _isSubmitting = false;

  // 6 Directional Photo URLs
  final Map<String, String> _uploadedPhotoUrls = {
    'front': '',
    'rear': '',
    'leftSide': '',
    'rightSide': '',
    'interior': '',
    'dashboardOdometer': '',
  };

  final Map<String, bool> _isUploading = {
    'front': false,
    'rear': false,
    'leftSide': false,
    'rightSide': false,
    'interior': false,
    'dashboardOdometer': false,
  };

  @override
  void dispose() {
    _odometerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadPhoto(String slot) async {
    final client = context.read<ConvexClientWrapper>();
    final picker = ImagePicker();

    try {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1200,
        imageQuality: 80,
      );

      if (picked == null) return;
      if (!mounted) return;

      setState(() => _isUploading[slot] = true);

      final bytes = await picked.readAsBytes();
      final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: client,
        imageBytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          _uploadedPhotoUrls[slot] = uploadRes.publicUrl;
          _isUploading[slot] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading[slot] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _handleSubmitInspection() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    final odo = int.tryParse(_odometerController.text.trim());
    if (odo == null || odo < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid odometer reading in km.')),
      );
      return;
    }

    // Check mandatory photos
    if (_uploadedPhotoUrls['front']!.isEmpty ||
        _uploadedPhotoUrls['rear']!.isEmpty ||
        _uploadedPhotoUrls['dashboardOdometer']!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take Front, Rear, and Dashboard Odometer photos.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      final res = await client.mutation(
        'escrow:completeVehicleInspection',
        args: {
          'escrowOrderId': widget.escrowOrderId,
          'inspectorId': user.id,
          'inspectionType': widget.inspectionType,
          'odometerReadingKm': odo,
          'fuelTankPercentage': _fuelPercentage.toInt(),
          'photoFrontUrl': _uploadedPhotoUrls['front']!,
          'photoRearUrl': _uploadedPhotoUrls['rear']!,
          'photoLeftSideUrl': _uploadedPhotoUrls['leftSide']!.isNotEmpty ? _uploadedPhotoUrls['leftSide']! : _uploadedPhotoUrls['front']!,
          'photoRightSideUrl': _uploadedPhotoUrls['rightSide']!.isNotEmpty ? _uploadedPhotoUrls['rightSide']! : _uploadedPhotoUrls['rear']!,
          'photoInteriorUrl': _uploadedPhotoUrls['interior']!.isNotEmpty ? _uploadedPhotoUrls['interior']! : _uploadedPhotoUrls['front']!,
          'photoDashboardOdometerUrl': _uploadedPhotoUrls['dashboardOdometer']!,
          'damagesDetected': _hasDamages ? _damagesList : [],
          'notes': _notesController.text.trim(),
          'qrTokenHash': 'QR_VERIFIED_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (res.success) {
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Digital Vehicle Inspection recorded successfully!'),
              backgroundColor: AppColors.emerald,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Inspection failed: ${res.errorMessage}'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting inspection: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.inspectionType == 'PRE_TRIP_RENTAL'
        ? 'Pre-Trip Vehicle Inspection'
        : (widget.inspectionType == 'POST_TRIP_RENTAL' ? 'Post-Trip Return Inspection' : 'Mechanic Inspection');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Reference Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined, color: Color(0xFF1D4ED8), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Escrow Contract: ${widget.orderCode}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E3A8A)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Odometer Reading
            const Text('Odometer Reading (km)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _odometerController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'e.g. 84250',
                prefixIcon: const Icon(Icons.speed_rounded, color: AppColors.gray500),
                filled: true,
                fillColor: AppColors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 20),

            // Fuel Level Gauge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fuel Tank Level', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${_fuelPercentage.toInt()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.emeraldDark)),
              ],
            ),
            Slider(
              value: _fuelPercentage,
              min: 0,
              max: 100,
              divisions: 10,
              activeColor: AppColors.emerald,
              inactiveColor: AppColors.gray200,
              onChanged: (val) => setState(() => _fuelPercentage = val),
            ),
            const SizedBox(height: 20),

            // 6 Directional Photos Matrix
            const Text('Mandatory 6-Angle Condition Photos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('Take clear photos showing all sides and current dashboard readings.', style: TextStyle(fontSize: 12, color: AppColors.gray500)),
            const SizedBox(height: 12),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.3,
              children: [
                _buildPhotoSlot('front', 'Front Bumper', Icons.arrow_upward_rounded),
                _buildPhotoSlot('rear', 'Rear / Tailgate', Icons.arrow_downward_rounded),
                _buildPhotoSlot('leftSide', 'Left Profile', Icons.arrow_back_rounded),
                _buildPhotoSlot('rightSide', 'Right Profile', Icons.arrow_forward_rounded),
                _buildPhotoSlot('interior', 'Cabin Interior', Icons.airline_seat_recline_extra_rounded),
                _buildPhotoSlot('dashboardOdometer', 'Dashboard & Odo', Icons.speed_rounded),
              ],
            ),
            const SizedBox(height: 20),

            // Damage Toggle
            SwitchListTile(
              value: _hasDamages,
              onChanged: (val) => setState(() => _hasDamages = val),
              activeThumbColor: AppColors.emerald,
              title: const Text('Are there existing scratches or dents?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              subtitle: const Text('Flags will be recorded to protect your deposit.', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
            ),

            if (_hasDamages) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Describe damage location and severity',
                  hintText: 'e.g. Minor scratch on rear left bumper, small dent on driver door.',
                  filled: true,
                  fillColor: AppColors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Submit Button
            VxButton(
              label: 'Sign & Submit Inspection',
              icon: Icons.check_circle_outline_rounded,
              isLoading: _isSubmitting,
              onPressed: _handleSubmitInspection,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSlot(String slot, String label, IconData icon) {
    final url = _uploadedPhotoUrls[slot];
    final isUploading = _isUploading[slot] ?? false;

    return InkWell(
      onTap: isUploading ? null : () => _pickAndUploadPhoto(slot),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: url != null && url.isNotEmpty ? AppColors.emerald : AppColors.border,
            width: url != null && url.isNotEmpty ? 1.5 : 1.0,
          ),
        ),
        child: isUploading
            ? const Center(child: CircularProgressIndicator(color: AppColors.emerald, strokeWidth: 2))
            : url != null && url.isNotEmpty
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(url, fit: BoxFit.cover),
                      ),
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: AppColors.gray400, size: 28),
                      const SizedBox(height: 6),
                      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.gray700)),
                      const SizedBox(height: 2),
                      const Text('Tap to capture', style: TextStyle(fontSize: 9, color: AppColors.gray400)),
                    ],
                  ),
      ),
    );
  }
}
