import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/repositories/auth_repository.dart';

/// Enter the 6-digit code mailed to the account's address.
///
/// "Verified" is shown ONLY after the server confirmed the code ([AuthRepository.verifyEmail]
/// returned without an error); nothing here sets a local flag on its own.
class EmailVerificationPanel extends StatefulWidget {
  final AuthRepository repository;
  final String email;

  /// Called once, after the server confirmed the email.
  final VoidCallback onVerified;

  /// Minimum wait before the next "Send a new code" (the server also enforces its own limit).
  final Duration resendCooldown;

  const EmailVerificationPanel({
    super.key,
    required this.repository,
    required this.email,
    required this.onVerified,
    this.resendCooldown = const Duration(seconds: 60),
  });

  @override
  State<EmailVerificationPanel> createState() => _EmailVerificationPanelState();
}

class _EmailVerificationPanelState extends State<EmailVerificationPanel> {
  final _code = TextEditingController();
  Timer? _timer;
  bool _busy = false;
  bool _verified = false;
  String? _error;
  String? _info;
  int _cooldownLeft = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldownLeft = widget.resendCooldown.inSeconds);
    if (_cooldownLeft <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldownLeft = _cooldownLeft > 0 ? _cooldownLeft - 1 : 0);
      if (_cooldownLeft == 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Enter the 6-digit code from your email.';
        _info = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.repository.verifyEmail(code: code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _verified = true;
      });
      widget.onVerified();
    } on AuthException catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not verify your email. Check your connection and try again.';
      });
    }
  }

  Future<void> _resend() async {
    if (_busy || _cooldownLeft > 0) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.repository.resendEmailVerification();
      if (!mounted) return;
      _code.clear();
      setState(() {
        _busy = false;
        _info = 'A new code has been sent to ${widget.email}.';
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send a new code. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verified) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.verified_rounded, color: AppColors.emeraldDark, size: 44),
          SizedBox(height: 12),
          Text('Email verified',
              key: Key('email-verify-success'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          SizedBox(height: 6),
          Text('Your email address is confirmed.', textAlign: TextAlign.center),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your email is not verified yet. Enter the 6-digit code we sent to ${widget.email}. '
          'The code is valid for 10 minutes.',
          key: const Key('email-verify-explainer'),
          style: const TextStyle(color: AppColors.gray500, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('email-verify-code'),
          controller: _code,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: const InputDecoration(counterText: '', hintText: '000000', border: OutlineInputBorder()),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, key: const Key('email-verify-error'), style: const TextStyle(color: AppColors.error)),
          ),
        if (_info != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_info!, key: const Key('email-verify-info'), style: const TextStyle(color: AppColors.emeraldDark)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('email-verify-submit'),
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify email'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('email-verify-resend'),
          onPressed: (_busy || _cooldownLeft > 0) ? null : _resend,
          child: Text(_cooldownLeft > 0 ? 'Send a new code in ${_cooldownLeft}s' : 'Send a new code'),
        ),
      ],
    );
  }
}

/// Full-screen version, shown right after registration. The user may skip: unverified accounts keep
/// the access they have today, but nothing here ever pretends the email is verified.
class VerifyEmailScreen extends StatefulWidget {
  final String email;

  /// Where to go after verifying or skipping.
  final VoidCallback onContinue;

  const VerifyEmailScreen({super.key, required this.email, required this.onContinue});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _verified = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Verify your email'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmailVerificationPanel(
                repository: context.read<AuthRepository>(),
                email: widget.email,
                onVerified: () => setState(() => _verified = true),
              ),
              const SizedBox(height: 12),
              if (_verified)
                FilledButton(
                  key: const Key('email-verify-continue'),
                  onPressed: widget.onContinue,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Continue'),
                )
              else
                TextButton(
                  key: const Key('email-verify-skip'),
                  onPressed: widget.onContinue,
                  child: const Text('Skip for now'),
                ),
              if (!_verified)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'You can verify later from Account & Profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.gray500, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
