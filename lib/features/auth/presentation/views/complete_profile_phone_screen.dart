// lib/features/auth/presentation/views/complete_profile_phone_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Complete Profile Phone Screen
// Mandatory phone linking for zero-cost Social Auth users so escrow
// balance, ledger payouts, and carrier mobile money routing are ready.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/carrier_detection_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/universal_phone_input.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class CompleteProfilePhoneScreen extends StatefulWidget {
  final UserEntity user;

  const CompleteProfilePhoneScreen({
    super.key,
    required this.user,
  });

  @override
  State<CompleteProfilePhoneScreen> createState() =>
      _CompleteProfilePhoneScreenState();
}

class _CompleteProfilePhoneScreenState
    extends State<CompleteProfilePhoneScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  SierraLeoneCarrier _selectedCarrier = SierraLeoneCarrier.unknown;
  String? _validationError;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onCarrierChanged(SierraLeoneCarrier carrier) {
    setState(() => _selectedCarrier = carrier);
  }

  bool _validatePhone(String input) {
    final clean = input.replaceAll(RegExp(r'\D'), '');
    // Sierra Leone numbers: either 8 digits (without leading 0) or 9 digits (with leading 0)
    // e.g. 76123456 or 076123456, or with country code 23276123456
    String national = clean;
    if (national.startsWith('232')) {
      national = national.substring(3);
    }
    if (national.startsWith('0')) {
      national = national.substring(1);
    }

    if (national.length != 8) {
      setState(() {
        _validationError =
            'Please enter a valid 8-digit Sierra Leone mobile number (e.g. 076 123 456)';
      });
      return false;
    }

    setState(() => _validationError = null);
    return true;
  }

  void _onSubmit() {
    final raw = _phoneController.text.trim();
    if (!_validatePhone(raw)) return;

    String clean = raw.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('232')) {
      clean = clean.substring(3);
    }
    if (clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    final formatted = '+232$clean';

    context.read<AuthBloc>().add(LinkPhoneNumberEvent(
          userId: widget.user.id,
          phoneNumber: formatted,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.authenticated && state.user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage ?? 'Account setup complete!'),
              backgroundColor: AppColors.emerald,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainNavigationShell()),
            (route) => false,
          );
        } else if (state.status == AuthStatus.error &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: PopScope(
        canPop: false, // Non-dismissible mandatory profile completion
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ── Brand & Security Icon ─────────────────────────
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phonelink_setup_rounded,
                          size: 38,
                          color: AppColors.emerald,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── User Avatar & Welcome ──────────────────────────
                    if (widget.user.avatarUrl != null &&
                        widget.user.avatarUrl!.isNotEmpty)
                      Center(
                        child: CircleAvatar(
                          radius: 28,
                          backgroundImage:
                              NetworkImage(widget.user.avatarUrl!),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Title & Subtitle ──────────────────────────────
                    Text(
                      'Complete Your Vektolux Account',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.obsidian,
                                letterSpacing: -0.5,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your Sierra Leone mobile number for escrow payouts, booking receipts, and mobile money transactions.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                    ),

                    const SizedBox(height: 28),

                    // ── Phone Input with Carrier Detection & Override ─
                    UniversalPhoneInput(
                      controller: _phoneController,
                      label: 'Sierra Leone Mobile Number',
                      hint: 'e.g. 076 123 456 or 077 123 456',
                      onCarrierChanged: _onCarrierChanged,
                    ),

                    if (_validationError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.error, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _validationError!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_selectedCarrier != SierraLeoneCarrier.unknown) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: AppColors.emerald, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Routing to ${_selectedCarrier.displayName}',
                            style: const TextStyle(
                              color: AppColors.emeraldDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Escrow Notice Pill ────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.emerald.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            color: AppColors.emeraldDark,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Protected Escrow & Instant Payouts',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.emeraldDark,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your number will be linked to your Orange Money, Afrimoney, or QMoney wallet for verified peer-to-peer settlements.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.emeraldDark
                                        .withValues(alpha: 0.9),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Submit Button ─────────────────────────────────
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading =
                            state.status == AuthStatus.linkingPhone;
                        return SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _onSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.emerald,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save & Continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
