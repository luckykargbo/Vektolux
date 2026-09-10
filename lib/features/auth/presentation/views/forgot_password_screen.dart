// lib/features/auth/presentation/views/forgot_password_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Self-Service Password Recovery
// Enables multi-channel OTP recovery via SMS, WhatsApp, and Email.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialIdentifier;

  const ForgotPasswordScreen({
    super.key,
    this.initialIdentifier,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _currentStep = 0; // 0: Request, 1: Enter OTP, 2: New Password
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _deliveryChannel = 'sms'; // 'sms', 'whatsapp', 'email'
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;
  String? _activeDemoCode;

  Timer? _countdownTimer;
  int _secondsRemaining = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialIdentifier != null && widget.initialIdentifier!.isNotEmpty) {
      _identifierController.text = widget.initialIdentifier!;
      if (widget.initialIdentifier!.contains('@')) {
        _deliveryChannel = 'email';
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _countdownTimer?.cancel();
        setState(() => _canResend = true);
      }
    });
  }

  Future<void> _handleSendOtp() async {
    final id = _identifierController.text.trim();
    if (id.isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number or email address');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final result = await convexClient.mutation(
        'auth:sendPasswordResetOtp',
        args: {
          'identifier': id,
          'deliveryChannel': _deliveryChannel,
        },
      );

      if (!result.success || result.value == null) {
        throw Exception(result.errorMessage ?? 'Failed to send reset code');
      }

      final data = result.value as Map<String, dynamic>;
      setState(() {
        _isSubmitting = false;
        _currentStep = 1;
        _activeDemoCode = data['demoCode']?.toString();
        _successMessage = data['message']?.toString();
      });

      if (_activeDemoCode != null) {
        _otpController.text = _activeDemoCode!;
      }

      _startResendCountdown();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _handleVerifyAndReset() async {
    final otp = _otpController.text.trim();
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code');
      return;
    }
    if (newPass.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final result = await convexClient.mutation(
        'auth:verifyResetOtpAndSetPassword',
        args: {
          'identifier': _identifierController.text.trim(),
          'otpCode': otp,
          'newPassword': newPass,
        },
      );

      if (!result.success || result.value == null) {
        throw Exception(result.errorMessage ?? 'Verification failed');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Password updated successfully! Please sign in.'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.obsidian),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.obsidian,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Icon
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: AppColors.emeraldDark,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Center(
                child: Text(
                  _currentStep == 0
                      ? 'Forgot Your Password?'
                      : 'Enter Verification Code',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _currentStep == 0
                      ? 'Select your delivery method and we will send a 6-digit verification code.'
                      : 'We dispatched a 6-digit code to ${_identifierController.text.trim()}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.gray600,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.emerald.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppColors.emeraldDark, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: AppColors.emeraldDark, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_currentStep == 0) ...[
                // Delivery Channel Selector
                const Text(
                  'Choose Verification Channel',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    _buildChannelOption(
                      title: 'SMS',
                      channel: 'sms',
                      icon: Icons.sms_rounded,
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    _buildChannelOption(
                      title: 'WhatsApp',
                      channel: 'whatsapp',
                      icon: Icons.chat_bubble_rounded,
                      color: const Color(0xFF25D366),
                    ),
                    const SizedBox(width: 8),
                    _buildChannelOption(
                      title: 'Email',
                      channel: 'email',
                      icon: Icons.email_rounded,
                      color: const Color(0xFF0284C7),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Identifier Input
                TextFormField(
                  controller: _identifierController,
                  keyboardType: _deliveryChannel == 'email'
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                  style: const TextStyle(
                    color: AppColors.obsidian,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    labelText: _deliveryChannel == 'email'
                        ? 'Email Address'
                        : 'Sierra Leone Phone Number',
                    hintText: _deliveryChannel == 'email'
                        ? 'e.g. user@vektolux.sl'
                        : '+232 76 123456',
                    prefixIcon: Icon(
                      _deliveryChannel == 'email'
                          ? Icons.email_outlined
                          : Icons.phone_outlined,
                      color: AppColors.obsidian,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isSubmitting ? null : _handleSendOtp,
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Send Verification Code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ] else ...[
                // OTP Code Input
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.obsidian,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    labelText: '6-Digit OTP Code',
                    hintText: '123456',
                    counterText: '',
                    prefixIcon: Icon(Icons.key_rounded, color: AppColors.obsidian),
                  ),
                ),
                const SizedBox(height: 16),

                // New Password Input
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  style: const TextStyle(
                    color: AppColors.obsidian,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    hintText: 'At least 6 characters',
                    prefixIcon: Icon(Icons.lock_outline_rounded, color: AppColors.obsidian),
                  ),
                ),
                const SizedBox(height: 14),

                // Confirm Password Input
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  style: const TextStyle(
                    color: AppColors.obsidian,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    hintText: 'Re-enter your new password',
                    prefixIcon: Icon(Icons.lock_rounded, color: AppColors.obsidian),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isSubmitting ? null : _handleVerifyAndReset,
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Update Password & Sign In', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 14),

                // Resend Timer Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _canResend
                          ? "Didn't receive the code?"
                          : "Resend available in ${_secondsRemaining}s",
                      style: const TextStyle(fontSize: 12, color: AppColors.gray600),
                    ),
                    if (_canResend) ...[
                      TextButton(
                        onPressed: _isSubmitting ? null : _handleSendOtp,
                        child: const Text('Resend Code', style: TextStyle(color: AppColors.emerald, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelOption({
    required String title,
    required String channel,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _deliveryChannel == channel;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _deliveryChannel = channel),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : AppColors.gray500, size: 22),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.obsidian : AppColors.gray600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
