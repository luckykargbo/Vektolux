// lib/features/auth/presentation/views/mfa_code_dialog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Two-factor code entry
// Shown when the server says the account needs its second factor (password login or Google/Apple
// sign-in). Nothing here creates a session: it only collects the code and hands it to the BLoC.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

class MfaCodeDialog extends StatefulWidget {
  const MfaCodeDialog({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.errorMessage,
    this.verifying = false,
  });

  /// Called with the trimmed code (6-digit authenticator code or a backup code).
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final String? errorMessage;
  final bool verifying;

  @override
  State<MfaCodeDialog> createState() => _MfaCodeDialogState();
}

class _MfaCodeDialogState extends State<MfaCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isEmpty || widget.verifying) return;
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // back is "Cancel": it must burn the pending challenge, not just hide the dialog
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !widget.verifying) widget.onCancel();
      },
      child: AlertDialog(
        title: const Text('Two-factor authentication'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the 6-digit code from your authenticator app, or one of your emergency backup codes.',
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Two-factor authentication code',
                textField: true,
                child: TextField(
                  key: const Key('mfa-code-field'),
                  controller: _controller,
                  autofocus: true,
                  enabled: !widget.verifying,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword, // backup codes contain letters
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(16),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z\- ]')),
                  ],
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Authentication code',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.errorMessage!,
                    key: const Key('mfa-error'),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('mfa-cancel'),
            onPressed: widget.verifying ? null : widget.onCancel,
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('mfa-submit'),
            onPressed: widget.verifying ? null : _submit,
            child: widget.verifying
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Verify'),
          ),
        ],
      ),
    );
  }
}
