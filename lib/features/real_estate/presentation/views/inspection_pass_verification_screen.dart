// lib/features/real_estate/presentation/views/inspection_pass_verification_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Agent Inspection Pass Verification Portal
// Allows certified field agents to input client's 4-digit OTP or scan QR hash.
// Executes mutual verification, releases 85% payout to agent's wallet,
// and unmasks landlord direct contact & exact coordinates for the client.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class InspectionPassVerificationScreen extends StatefulWidget {
  final String? initialPassId;

  const InspectionPassVerificationScreen({
    super.key,
    this.initialPassId,
  });

  @override
  State<InspectionPassVerificationScreen> createState() =>
      _InspectionPassVerificationScreenState();
}

class _InspectionPassVerificationScreenState
    extends State<InspectionPassVerificationScreen> {
  final _passIdController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isVerifying = false;
  Map<String, dynamic>? _verificationResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialPassId != null) {
      _passIdController.text = widget.initialPassId!;
    }
  }

  @override
  void dispose() {
    _passIdController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final passId = _passIdController.text.trim();
    final otp = _otpController.text.trim();

    if (passId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the Inspection Pass ID or reference.')),
      );
      return;
    }

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the client’s 4-digit verification OTP.')),
      );
      return;
    }

    final client = context.read<ConvexClientWrapper>();
    final user = context.read<AuthBloc>().state.user;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    double? lat;
    double? lng;

    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // Graceful GPS fallback if permissions denied
    }

    try {
      final res = await client.mutation(
        'realEstateEscrow:verifyInspectionPass',
        args: {
          'passId': passId,
          'agentId': user?.id,
          'otpOrQrHash': otp,
          if (lat != null) 'agentGpsLat': lat,
          if (lng != null) 'agentGpsLng': lng,
        },
      );

      if (res.success && res.value != null) {
        setState(() {
          _isVerifying = false;
          _verificationResult = Map<String, dynamic>.from(res.value as Map);
        });
      } else {
        setState(() {
          _isVerifying = false;
          _errorMessage = res.errorMessage ?? 'OTP or Pass ID verification failed.';
        });
      }
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Verification error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Agent Pass Verification',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _verificationResult != null
            ? _buildSuccessView()
            : _buildInputForm(),
      ),
    );
  }

  Widget _buildInputForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.emerald, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Field Agent Settlement Portal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Verify client physical arrival. Instantly receives 85% net tour fee and unlocks unmasked property contact.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Pass ID Input
        const Text(
          'INSPECTION PASS ID / REFERENCE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passIdController,
          decoration: InputDecoration(
            hintText: 'e.g. js732abc910... or pass token',
            prefixIcon: const Icon(Icons.confirmation_number_outlined, color: AppColors.gray500),
            filled: true,
            fillColor: AppColors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 20),

        // 4-Digit OTP Input
        const Text(
          'CLIENT 4-DIGIT VERIFICATION OTP',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '0000',
            filled: true,
            fillColor: AppColors.white,
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 28),

        VxButton.primary(
          text: _isVerifying ? 'Verifying & Settling...' : 'Verify Pass & Collect 85% Fee',
          icon: Icons.check_circle_outline_rounded,
          onPressed: _isVerifying ? null : _handleVerify,
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    final res = _verificationResult!;
    final agentPayout = res['agentDisbursedAmount'] ?? 85.0;
    final landlordContact = res['unmaskedContact'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.emerald.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.emeraldSurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.emerald, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tour Verified Successfully!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'SLE ${agentPayout.toStringAsFixed(2)} Disbursed',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.emeraldDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Net 85% tour fee credited directly to your Agent Wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.gray600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Unmasked Landlord Details
        if (landlordContact != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.emerald.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_open_rounded, color: AppColors.emerald, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'UNMASKED LANDLORD DIRECT CONTACT',
                      style: TextStyle(
                        color: AppColors.emeraldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildContactRow(
                  Icons.person,
                  'Landlord / Owner',
                  landlordContact['name']?.toString() ?? 'Verified Owner',
                ),
                const SizedBox(height: 10),
                _buildContactRow(
                  Icons.phone,
                  'Phone Number',
                  landlordContact['phone']?.toString() ?? '+232-xx-xxx-xxx',
                ),
                if (landlordContact['address'] != null) ...[
                  const SizedBox(height: 10),
                  _buildContactRow(
                    Icons.location_on,
                    'Exact Plot / Street Address',
                    landlordContact['address'].toString(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        VxButton.primary(
          text: 'Verify Another Tour',
          icon: Icons.refresh_rounded,
          onPressed: () {
            setState(() {
              _verificationResult = null;
              _passIdController.clear();
              _otpController.clear();
            });
          },
        ),
      ],
    );
  }

  Widget _buildContactRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
