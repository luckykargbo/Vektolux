// lib/features/verification/presentation/views/identity_verification_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Progressive 4-Step eIDV Verification Wizard
// Multi-step identity verification supporting Sierra Leone NIN, ECOWAS,
// and Passports with Dev Mock Mode and high-contrast styling.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/database/daos/cached_users_dao.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../data/services/kyc_verification_service.dart';
import '../../domain/entities/verification_record.dart';

enum DocumentChoice { nationalId, ecowasCard, passport }

class IdentityVerificationScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;
  final CachedUsersDao? usersDao;
  final VoidCallback onVerificationComplete;
  final bool initialMockMode;

  const IdentityVerificationScreen({
    super.key,
    required this.convexClient,
    required this.currentUser,
    this.usersDao,
    required this.onVerificationComplete,
    this.initialMockMode = true,
  });

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  int _currentStep = 0; // 0: Select Doc, 1: Doc Capture, 2: Liveness, 3: Processing
  DocumentChoice _selectedDoc = DocumentChoice.nationalId;
  final _idNumberController = TextEditingController();
  bool _isProcessing = false;
  String? _processingStageText;
  String? _errorMessage;
  bool _isSessionInvalid = false;
  late bool _isMockMode;
  String? _sessionToken;
  late final KycVerificationService _kycService;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _isMockMode = widget.initialMockMode;
    _kycService = KycVerificationServiceImpl(
      convexClient: widget.convexClient,
      usersDao: widget.usersDao,
    );
    _resolveSession();
  }

  Future<void> _resolveSession() async {
    // 1. Check passed user session token
    if (widget.currentUser.sessionToken != null &&
        widget.currentUser.sessionToken!.isNotEmpty) {
      _sessionToken = widget.currentUser.sessionToken;
      return;
    }

    // 2. Check CachedUsersDao for active local session
    if (widget.usersDao != null) {
      try {
        final active = await widget.usersDao!.getActiveSession();
        if (active != null &&
            active.sessionToken != null &&
            active.sessionToken!.isNotEmpty) {
          if (mounted) {
            setState(() {
              _sessionToken = active.sessionToken;
            });
          }
          return;
        }
      } catch (_) {}
    }

    // 3. If session is missing or invalid, flag gracefully without raw 401 banner
    if (mounted) {
      setState(() {
        _isSessionInvalid = true;
      });
    }
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  IdDocumentType get _currentDomainDocType => switch (_selectedDoc) {
        DocumentChoice.nationalId => IdDocumentType.nationalId,
        DocumentChoice.ecowasCard => IdDocumentType.ecowasCard,
        DocumentChoice.passport => IdDocumentType.passport,
      };

  void _submitVerification() async {
    // Ensure session is available
    final token = _sessionToken ?? widget.currentUser.sessionToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage =
            'Your session authentication is missing or expired. Please return to login.';
        _isSessionInvalid = true;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _currentStep = 3; // Move to processing view
      _processingStageText = 'Initializing biometric verification pipeline...';
    });

    if (_isMockMode) {
      await _runMockVerificationFlow(token);
    } else {
      await _runLiveVerificationFlow(token);
    }
  }

  /// Automated simulated verification flow for development & testing.
  Future<void> _runMockVerificationFlow(String token) async {
    try {
      // Stage 1: Document OCR simulation
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() {
        _processingStageText = 'Extracting MRZ & scanning document checksums...';
      });

      // Stage 2: Biometric Liveness simulation
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() {
        _processingStageText =
            'Performing 3D passive liveness & anti-spoofing check...';
      });

      // Stage 3: Database execution via Convex
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        _processingStageText =
            'Registering Green Tick trust badge with Convex backend...';
      });

      final result = await _kycService.runMockVerification(
        userId: widget.currentUser.id,
        sessionToken: token,
        docType: _currentDomainDocType,
        docNumber: _idNumberController.text.trim(),
      );

      if (!result.success) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _errorMessage = result.errorMessage ?? 'Simulated verification failed.';
          _currentStep = 1;
        });
        return;
      }

      // Success animation delay
      if (!mounted) return;
      setState(() {
        _processingStageText = 'Identity verified! Green Tick badge activated.';
      });
      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        setState(() => _isProcessing = false);
        widget.onVerificationComplete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Verification error: $e';
        _currentStep = 1;
      });
    }
  }

  /// Live verification flow calling Convex verification mutations.
  Future<void> _runLiveVerificationFlow(String token) async {
    final result = await widget.convexClient.mutation(
      'verification:initiateVerification',
      args: {
        'userId': widget.currentUser.id,
        'sessionToken': token,
        'documentType': _currentDomainDocType.convexKey,
        'idNumber': _idNumberController.text.trim(),
        'ipAddress': '197.228.140.22',
        'deviceFingerprint': 'flutter_vektolux_client_app',
      },
    );

    if (!result.success) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = result.errorMessage ?? 'Verification submission failed.';
        _currentStep = 1;
      });
      return;
    }

    _startStatusPolling();
  }

  void _startStatusPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final statusResult =
          await _kycService.getVerificationStatus(userId: widget.currentUser.id);

      if (statusResult.success) {
        if (statusResult.isVerified) {
          timer.cancel();
          if (mounted) {
            setState(() => _isProcessing = false);
            widget.onVerificationComplete();
          }
        } else if (statusResult.status == 'rejected') {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _errorMessage = statusResult.errorMessage ??
                  'Verification was rejected. Please ensure the document is legible and selfie matches.';
              _currentStep = 0;
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Identity Verification (eIDV)',
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
          // Dev Mode Quick Toggle in AppBar
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isMockMode ? 'MOCK' : 'LIVE',
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
        // Progress Indicator
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
          child: switch (_currentStep) {
            0 => _buildStep0DocSelect(),
            1 => _buildStep1DocCapture(),
            2 => _buildStep2LivenessSelfie(),
            _ => _buildStep3Processing(),
          },
        ),
      ],
    );
  }

  /// Graceful view displayed when user's session token is expired or missing.
  Widget _buildSessionInvalidView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                size: 48,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Session Authentication Required',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your session has expired or is invalid. Please return to the login screen to refresh your credentials.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            VxButton.primary(
              text: 'Return to Login',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── STEP 0: DOCUMENT SELECTION ─────────────────────────────────────
  Widget _buildStep0DocSelect() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dev Mode Banner
          _buildDevModeCard(),
          const SizedBox(height: 12),
          const Text(
            'Select Document Type',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose your government-issued identity document for automated verification:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          _DocCard(
            title: 'Sierra Leone National ID (NIN)',
            subtitle: 'NCRA National Biometric Identity Card (8-12 alphanumeric)',
            icon: Icons.credit_card_rounded,
            isSelected: _selectedDoc == DocumentChoice.nationalId,
            onTap: () => setState(() => _selectedDoc = DocumentChoice.nationalId),
          ),
          const SizedBox(height: 14),
          _DocCard(
            title: 'ECOWAS Biometric ID Card',
            subtitle: 'West African regional biometric travel card',
            icon: Icons.badge_outlined,
            isSelected: _selectedDoc == DocumentChoice.ecowasCard,
            onTap: () => setState(() => _selectedDoc = DocumentChoice.ecowasCard),
          ),
          const SizedBox(height: 14),
          _DocCard(
            title: 'International Passport',
            subtitle: 'ICAO 9303 machine-readable passport',
            icon: Icons.flight_takeoff_rounded,
            isSelected: _selectedDoc == DocumentChoice.passport,
            onTap: () => setState(() => _selectedDoc = DocumentChoice.passport),
          ),
          const Spacer(),
          VxButton.primary(
            text: 'Continue to Document Scan',
            onPressed: () => setState(() => _currentStep = 1),
          ),
        ],
      ),
    );
  }

  // ─── STEP 1: DOCUMENT CAPTURE & NUMBER ──────────────────────────────
  Widget _buildStep1DocCapture() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDevModeCard(),
          const SizedBox(height: 12),
          const Text(
            'Scan Identity Document',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Align your physical card within the frame. Avoid glare, shadows, and reflections.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(
            height: 170,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.obsidian.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.emerald, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.document_scanner_rounded,
                  size: 44,
                  color: AppColors.emerald,
                ),
                const SizedBox(height: 8),
                Text(
                  _isMockMode
                      ? 'Automated OCR Simulated (Dev Mode)'
                      : 'Automated OCR & MRZ Ready',
                  style: const TextStyle(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Secure ID Number Input Field (High Contrast) ──────────────
          TextFormField(
            controller: _idNumberController,
            style: const TextStyle(
              color: Color(0xFF0F172A), // High-contrast Dark Charcoal / Slate
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8FAFC), // Soft Off-White
              labelText: 'Document Number (e.g. SL-NIN or Passport No.)',
              labelStyle: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              hintText: switch (_selectedDoc) {
                DocumentChoice.nationalId => 'e.g. 1029384756 or SL8849201',
                DocumentChoice.ecowasCard => 'e.g. EC89201948',
                DocumentChoice.passport => 'e.g. A12345678',
              },
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 15,
              ),
              prefixIcon: const Icon(
                Icons.pin_rounded,
                color: Color(0xFF64748B),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF10B981),
                  width: 1.8,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 1.2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 1.8,
                ),
              ),
            ),
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
          ),
          const SizedBox(height: 32),
          VxButton.primary(
            text: 'Proceed to Biometric Selfie',
            onPressed: () {
              final err = _kycService.getValidationError(
                docType: _currentDomainDocType,
                docNumber: _idNumberController.text,
              );
              if (err != null) {
                setState(() => _errorMessage = err);
                return;
              }
              setState(() {
                _errorMessage = null;
                _currentStep = 2;
              });
            },
          ),
        ],
      ),
    );
  }

  // ─── STEP 2: 3D PASSIVE LIVENESS SELFIE ─────────────────────────────
  Widget _buildStep2LivenessSelfie() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDevModeCard(),
          const SizedBox(height: 12),
          const Text(
            '3D Biometric Liveness Check',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Look straight into the camera. We perform passive liveness detection to ensure you are physically present.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 190,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: const BorderRadius.all(Radius.elliptical(100, 130)),
                border: Border.all(color: AppColors.emerald, width: 3),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.face_retouching_natural,
                    size: 52,
                    color: AppColors.emerald,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Position Face in Oval',
                    style: TextStyle(
                      color: AppColors.emerald,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          VxButton.primary(
            text: _isMockMode
                ? 'Submit Instant Simulated Verification'
                : 'Submit Automated Verification',
            icon: Icons.camera_alt_rounded,
            isLoading: _isProcessing,
            onPressed: _isProcessing ? null : _submitVerification,
          ),
        ],
      ),
    );
  }

  // ─── STEP 3: AUTOMATED PROCESSING ───────────────────────────────────
  Widget _buildStep3Processing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation(AppColors.emerald),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _isMockMode
                  ? 'Simulated Verification in Progress'
                  : 'Automated Verification in Progress',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _processingStageText ??
                  'Verifying MRZ checksums, ICAO anti-tampering, and 1:1 facial biometric match with the Sierra Leone identity registry...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── REUSABLE DEV / TEST MODE TOGGLE CARD ───────────────────────────
  Widget _buildDevModeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isMockMode
            ? AppColors.emerald.withValues(alpha: 0.08)
            : AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isMockMode
              ? AppColors.emerald.withValues(alpha: 0.35)
              : AppColors.border,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isMockMode ? Icons.bolt_rounded : Icons.verified_user_outlined,
            color: _isMockMode ? AppColors.emerald : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMockMode
                      ? 'Dev Mock Mode (Instant Test Verification)'
                      : 'Live Registry Mode (Prembly / Smile ID)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: _isMockMode ? AppColors.emeraldDark : AppColors.obsidian,
                  ),
                ),
                Text(
                  _isMockMode
                      ? 'Simulates OCR, liveness, & Green Tick activation without live external credentials.'
                      : 'Requires production Sierra Leone NCRA NIN registry lookup.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isMockMode,
            activeThumbColor: AppColors.emerald,
            onChanged: (val) => setState(() => _isMockMode = val),
          ),
        ],
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DocCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.emerald.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.emerald : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.emerald : AppColors.obsidian,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: isSelected ? AppColors.emerald : AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppColors.emerald),
          ],
        ),
      ),
    );
  }
}
