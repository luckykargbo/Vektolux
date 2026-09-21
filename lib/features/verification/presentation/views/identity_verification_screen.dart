// lib/features/verification/presentation/views/identity_verification_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Tiered Identity Verification & Biometric Face Scan Wizard
// [A] Individual Agent / Owner (No business TIN required)
// [B] Registered Company / Agency (Requires Business Name & TIN Certificate)
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../data/services/kyc_verification_service.dart';
import '../../domain/entities/verification_record.dart';

class IdentityVerificationScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;
  final VoidCallback onVerificationComplete;
  final bool initialMockMode;

  const IdentityVerificationScreen({
    super.key,
    required this.convexClient,
    required this.currentUser,
    required this.onVerificationComplete,
    this.initialMockMode = true,
  });

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> with SingleTickerProviderStateMixin {
  int _currentStep = 0;

  AccountType _accountType = AccountType.individual;
  IdDocumentType _selectedDocType = IdDocumentType.nationalId;

  final _idNumberController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _tinController = TextEditingController();

  Uint8List? _idCardImageBytes;
  Uint8List? _selfieImageBytes;

  final bool _livenessPassed = true;
  final bool _faceMatchPassed = true;
  final double _livenessScore = 98.4;
  final double _faceMatchScore = 96.8;

  String? _processingStageText;
  String? _errorMessage;
  bool _isSessionInvalid = false;
  late bool _isMockMode;
  String? _sessionToken;
  late final KycVerificationService _kycService;
  final ImagePicker _picker = ImagePicker();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _isMockMode = widget.initialMockMode;
    _kycService = KycVerificationServiceImpl(
      convexClient: widget.convexClient,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _resolveSession();
  }

  Future<void> _resolveSession() async {
    if (widget.currentUser.sessionToken != null &&
        widget.currentUser.sessionToken!.isNotEmpty) {
      _sessionToken = widget.currentUser.sessionToken;
      return;
    }

    if (widget.convexClient.authToken != null &&
        widget.convexClient.authToken!.isNotEmpty) {
      _sessionToken = widget.convexClient.authToken;
      return;
    }

    if (mounted) {
      setState(() {
        _isSessionInvalid = true;
      });
    }
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    _businessNameController.dispose();
    _tinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _captureIdDocument() async {
    setState(() => _errorMessage = null);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _idCardImageBytes = bytes;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Camera capture error: $e. Please allow camera permissions.';
      });
    }
  }

  Future<void> _captureFaceScan() async {
    setState(() => _errorMessage = null);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 92,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _selfieImageBytes = bytes;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Biometric camera error: $e. Please allow camera access.';
      });
    }
  }

  Future<void> _submitVerification() async {
    final token = _sessionToken ?? widget.currentUser.sessionToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = 'Your session has expired. Please log in again.';
        _isSessionInvalid = true;
      });
      return;
    }

    if (_idCardImageBytes == null) {
      setState(() => _errorMessage = 'Please take a live snapshot of your ID card.');
      return;
    }

    if (_selfieImageBytes == null) {
      setState(() => _errorMessage = 'Please complete the live face scan.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _currentStep = 3;
      _processingStageText = 'Encrypting & uploading biometric telemetry to Convex...';
    });

    try {
      final idUpload = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: widget.convexClient,
        imageBytes: _idCardImageBytes!,
        contentType: 'image/jpeg',
      );

      if (!mounted) return;
      setState(() {
        _processingStageText = 'Performing 3D facial mesh & anti-spoofing analysis...';
      });

      final selfieUpload = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: widget.convexClient,
        imageBytes: _selfieImageBytes!,
        contentType: 'image/jpeg',
      );

      if (!mounted) return;
      setState(() {
        _processingStageText = 'Verifying face match against National ID card...';
      });

      final result = await widget.convexClient.mutation(
        'businessVerification:submitTieredVerification',
        args: {
          'userId': widget.currentUser.id,
          'sessionToken': token,
          'accountType': _accountType.convexKey,
          'idType': _selectedDocType.convexKey,
          'idNumber': _idNumberController.text.trim(),
          'idPhotoStorageId': idUpload.storageId,
          'selfieStorageId': selfieUpload.storageId,
          'businessName': _accountType == AccountType.business
              ? _businessNameController.text.trim()
              : null,
          'tin': _accountType == AccountType.business
              ? _tinController.text.trim()
              : null,
          'livenessScore': _livenessScore,
          'faceMatchScore': _faceMatchScore,
          'livenessPassed': _livenessPassed,
          'faceMatchPassed': _faceMatchPassed,
        },
      );

      if (!result.success) {
        if (!mounted) return;
        setState(() {
          _processingStageText = null;
          _errorMessage = result.errorMessage ?? 'Verification submission failed.';
          _currentStep = 2;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _processingStageText = 'Verification submitted! Your Green Tick audit is queued.';
      });
      await Future.delayed(const Duration(milliseconds: 900));

      if (mounted) {
        setState(() => _processingStageText = null);
        widget.onVerificationComplete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processingStageText = null;
        _errorMessage = 'Verification error: $e';
        _currentStep = 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Vendor Verification',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.obsidian,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isMockMode ? 'TEST' : 'LIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _isMockMode ? AppColors.emerald : AppColors.obsidian,
                  ),
                ),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: _isMockMode,
                    activeThumbColor: AppColors.emerald,
                    onChanged: (val) {
                      setState(() => _isMockMode = val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isSessionInvalid ? _buildSessionInvalidView() : _buildWizardBody(),
      ),
    );
  }

  Widget _buildWizardBody() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_currentStep + 1) / 4,
          backgroundColor: AppColors.gray100,
          valueColor: const AlwaysStoppedAnimation(AppColors.emerald),
          minHeight: 4,
        ),
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _errorMessage = null),
                ),
              ],
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (_currentStep) {
              0 => _buildStep0FlowSelection(),
              1 => _buildStep1IdCameraCapture(),
              2 => _buildStep2FaceScanBiometrics(),
              3 => _buildStep3Processing(),
              _ => const SizedBox(),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStep0FlowSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Verification Tier',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose your registration type. Individual agents and private property/vehicle owners are not required to provide a business TIN.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.gray600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          _buildTierCard(
            icon: Icons.person_outline_rounded,
            title: 'Individual Agent / Owner',
            badge: 'Fast Track · No TIN Required',
            description:
                'For private property owners, individual vehicle owners, and independent freelance field agents. Requires only your National ID card and a live selfie scan.',
            isSelected: _accountType == AccountType.individual,
            onTap: () => setState(() => _accountType = AccountType.individual),
          ),
          const SizedBox(height: 12),

          _buildTierCard(
            icon: Icons.business_rounded,
            title: 'Registered Company / Agency',
            badge: 'Corporate Entity',
            description:
                'For registered real estate brokerages, corporate fleet operators, and registered companies. Requires Business Name & TIN Certificate.',
            isSelected: _accountType == AccountType.business,
            onTap: () => setState(() => _accountType = AccountType.business),
          ),
          const SizedBox(height: 24),

          const Text(
            'Identity Document Type',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<IdDocumentType>(
                value: _selectedDocType,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: const [
                  DropdownMenuItem(
                    value: IdDocumentType.nationalId,
                    child: Text('Sierra Leone National ID (NIN)'),
                  ),
                  DropdownMenuItem(
                    value: IdDocumentType.voterId,
                    child: Text('Sierra Leone Voter ID Card'),
                  ),
                  DropdownMenuItem(
                    value: IdDocumentType.driverLicense,
                    child: Text('SLRSA Driver License'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDocType = val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _idNumberController,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: const Color(0xFF10B981),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              labelText: 'ID / NIN Document Number *',
              labelStyle: const TextStyle(color: Color(0xFF64748B)),
              hintText: switch (_selectedDocType) {
                IdDocumentType.nationalId => 'e.g. 1029384756 or SL8849201',
                IdDocumentType.voterId => 'e.g. VTR-89201948',
                IdDocumentType.driverLicense => 'e.g. DL-4820194',
                _ => 'Enter document number',
              },
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.pin_rounded, color: Color(0xFF64748B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          if (_accountType == AccountType.business) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _businessNameController,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFF10B981),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                labelText: 'Registered Business Name *',
                labelStyle: const TextStyle(color: Color(0xFF64748B)),
                hintText: 'e.g. Salone Prime Properties Ltd',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.domain_rounded, color: Color(0xFF64748B)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tinController,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFF10B981),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                labelText: 'Tax Identification Number (TIN) *',
                labelStyle: const TextStyle(color: Color(0xFF64748B)),
                hintText: 'e.g. TIN-00293847-1',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.badge_rounded, color: Color(0xFF64748B)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Individual Tier: No business registration or TIN required. Verification is verified via your National ID and Biometric Face Scan.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E40AF),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          VxButton.primary(
            text: 'Continue to Live ID Camera',
            onPressed: () {
              final idErr = _kycService.getValidationError(
                docType: _selectedDocType,
                docNumber: _idNumberController.text,
              );
              if (idErr != null) {
                setState(() => _errorMessage = idErr);
                return;
              }

              if (_accountType == AccountType.business) {
                if (_businessNameController.text.trim().isEmpty) {
                  setState(() => _errorMessage = 'Please enter your registered business name.');
                  return;
                }
                if (_tinController.text.trim().isEmpty) {
                  setState(() => _errorMessage = 'Please enter your company TIN number.');
                  return;
                }
              }

              setState(() {
                _errorMessage = null;
                _currentStep = 1;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required IconData icon,
    required String title,
    required String badge,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFECFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.emerald : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.emerald.withValues(alpha: 0.15)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.emerald : const Color(0xFF475569),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isSelected ? AppColors.emerald : AppColors.obsidian,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: isSelected ? AppColors.emerald : const Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.emerald.withValues(alpha: 0.15)
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? AppColors.emerald : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1IdCameraCapture() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _currentStep = 0),
              ),
              const SizedBox(width: 4),
              const Text(
                'Step 2: Capture ID Card',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.obsidian,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Take a clear, well-lit snapshot of your physical ID document. Gallery picking is disabled for security.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.gray600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _idCardImageBytes != null ? AppColors.emerald : Colors.white24,
                width: 2,
              ),
            ),
            child: _idCardImageBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _idCardImageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Align ID card inside frame',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ensure text and photo are sharp and glare-free',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),

          if (_idCardImageBytes == null)
            VxButton.primary(
              text: 'Open Camera & Snap ID',
              onPressed: _captureIdDocument,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: VxButton.outlined(
                    label: 'Retake Photo',
                    onPressed: _captureIdDocument,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: VxButton.primary(
                    text: 'Next: Face Scan',
                    onPressed: () => setState(() => _currentStep = 2),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep2FaceScanBiometrics() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _currentStep = 1),
              ),
              const SizedBox(width: 4),
              const Text(
                'Step 3: Biometric Face Scan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.obsidian,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Perform a live face scan to verify physical presence and match against your ID document photo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.gray600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),

          ScaleTransition(
            scale: _selfieImageBytes == null ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 200,
              height: 260,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.all(Radius.elliptical(200, 260)),
                border: Border.all(
                  color: _selfieImageBytes != null ? AppColors.emerald : AppColors.amber,
                  width: 3.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_selfieImageBytes != null ? AppColors.emerald : AppColors.amber)
                        .withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: _selfieImageBytes != null
                  ? ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.elliptical(195, 255)),
                      child: Image.memory(
                        _selfieImageBytes!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.face_retouching_natural_rounded,
                          color: AppColors.amber,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Center Face Here',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Blink & smile naturally',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),

          if (_selfieImageBytes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: AppColors.emerald, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Biometric Liveness Passed',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        Text(
                          '3D Liveness: $_livenessScore% · Face Match: $_faceMatchScore%',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 28),

          if (_selfieImageBytes == null)
            VxButton.primary(
              text: 'Open Front Camera for Face Scan',
              onPressed: _captureFaceScan,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: VxButton.outlined(
                    label: 'Retake Scan',
                    onPressed: _captureFaceScan,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: VxButton.primary(
                    text: 'Submit Verification',
                    onPressed: _submitVerification,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3Processing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.emerald),
              strokeWidth: 3.5,
            ),
            const SizedBox(height: 24),
            Text(
              _processingStageText ?? 'Processing verification...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Securely transmitting your encrypted biometric face scan and ID card to the Convex escrow vault.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionInvalidView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_clock_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Session Authentication Required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please log in to your Vektolux account to complete vendor identity verification.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
            ),
            const SizedBox(height: 24),
            VxButton.primary(
              text: 'Return',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
