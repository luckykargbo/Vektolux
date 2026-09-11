// lib/features/auth/presentation/views/pending_verification_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Pending Business Verification Sandbox Screen
// Shown to agents/merchants whose verification is pending or rejected.
// Blocks access to the main app until an admin approves the application.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import 'login_screen.dart';

class PendingVerificationScreen extends StatefulWidget {
  final UserEntity user;

  const PendingVerificationScreen({super.key, required this.user});

  @override
  State<PendingVerificationScreen> createState() =>
      _PendingVerificationScreenState();
}

class _PendingVerificationScreenState
    extends State<PendingVerificationScreen> {
  // ── Live Status State ───────────────────────────────────────────────
  late String _verificationStatus;
  String? _businessName;
  String? _tinNumber;
  String? _documentUrl;
  String? _rejectionReason;

  bool _isRefreshing = false;

  // ── Resubmit State ──────────────────────────────────────────────────
  bool _showResubmitForm = false;
  final _businessNameController = TextEditingController();
  final _tinController = TextEditingController();
  String? _newDocumentFileName;
  int? _newDocumentFileSize;
  String? _newDocumentStorageId;
  bool _isUploadingDoc = false;
  bool _isResubmitting = false;
  String? _docError;
  String? _resubmitError;

  // ── Auto-poll Timer ─────────────────────────────────────────────────
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _verificationStatus = widget.user.verificationStatus;
    _businessName = widget.user.businessName;
    _tinNumber = widget.user.tinNumber;
    _documentUrl = widget.user.documentUrl;
    _rejectionReason = widget.user.rejectionReason;

    // Pre-fill resubmit form with existing data
    _businessNameController.text = widget.user.businessName ?? '';
    _tinController.text = widget.user.tinNumber ?? '';

    // Start polling every 30 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshStatus(silent: true);
    });

    // Initial live fetch
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _businessNameController.dispose();
    _tinController.dispose();
    super.dispose();
  }

  // ── Fetch Live Verification Status ──────────────────────────────────

  Future<void> _refreshStatus({bool silent = false}) async {
    if (!silent) setState(() => _isRefreshing = true);

    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final res = await convexClient.query(
        'businessVerification:getMyVerificationStatus',
        args: {
          'userId': widget.user.id,
          if (widget.user.sessionToken != null)
            'sessionToken': widget.user.sessionToken,
        },
      );

      if (res.success && res.value != null && mounted) {
        final data = res.value as Map<String, dynamic>;
        final newStatus = data['verificationStatus'] as String? ?? _verificationStatus;
        setState(() {
          _verificationStatus = newStatus;
          _businessName = data['businessName'] as String? ?? _businessName;
          _tinNumber = data['tinNumber'] as String? ?? _tinNumber;
          _documentUrl = data['documentUrl'] as String? ?? _documentUrl;
          _rejectionReason = data['rejectionReason'] as String?;
        });

        // If now approved, navigate to main app
        if (newStatus == 'approved' || newStatus == 'verified') {
          // Refresh the auth state so the user entity is updated
          if (mounted) {
            context.read<AuthBloc>().add(const RefreshUserSessionEvent());
          }
        }
      }
    } catch (_) {
      // Silent failures on auto-poll are fine
    } finally {
      if (mounted && !silent) setState(() => _isRefreshing = false);
    }
  }

  // ── Document Upload for Resubmission ────────────────────────────────

  Future<void> _pickResubmitDocument() async {
    setState(() => _docError = null);
    final convexClient = context.read<ConvexClientWrapper>();
    try {
      final file = await ImageUploadService.pickImageFromGallery();
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final size = bytes.lengthInBytes;

      const maxSizeBytes = 5 * 1024 * 1024;
      if (size > maxSizeBytes) {
        setState(() {
          _docError =
              'File exceeds 5MB limit (${(size / (1024 * 1024)).toStringAsFixed(1)} MB).';
        });
        return;
      }

      final name = file.name.toLowerCase();
      final isAllowed = name.endsWith('.pdf') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png');
      if (!isAllowed) {
        setState(() {
          _docError =
              'Invalid format. Only PDF, JPEG, and PNG files are allowed.';
        });
        return;
      }

      setState(() {
        _newDocumentFileName = file.name;
        _newDocumentFileSize = size;
        _isUploadingDoc = true;
      });

      final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: convexClient,
        imageBytes: bytes,
        contentType: file.mimeType ??
            (name.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg'),
      );

      if (mounted) {
        setState(() {
          _newDocumentStorageId = uploadRes.storageId;
          _isUploadingDoc = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingDoc = false;
          _docError = 'Document upload failed: $e';
        });
      }
    }
  }

  // ── Resubmit Verification ───────────────────────────────────────────

  Future<void> _resubmitVerification() async {
    final businessName = _businessNameController.text.trim();
    final tin = _tinController.text.trim();

    if (businessName.isEmpty) {
      setState(() => _resubmitError = 'Business name is required.');
      return;
    }
    if (tin.isEmpty) {
      setState(() => _resubmitError = 'TIN / Registration number is required.');
      return;
    }
    if (_newDocumentStorageId == null) {
      setState(() =>
          _resubmitError = 'Please upload a new proof document (PDF/JPEG/PNG ≤ 5MB).');
      return;
    }

    setState(() {
      _isResubmitting = true;
      _resubmitError = null;
    });

    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final res = await convexClient.mutation(
        'businessVerification:submitAgentVerification',
        args: {
          'userId': widget.user.id,
          if (widget.user.sessionToken != null)
            'sessionToken': widget.user.sessionToken,
          'businessName': businessName,
          'tinNumber': tin,
          'documentStorageId': _newDocumentStorageId!,
        },
      );

      if (res.success && mounted) {
        setState(() {
          _showResubmitForm = false;
          _verificationStatus = 'pending';
          _businessName = businessName;
          _tinNumber = tin;
          _rejectionReason = null;
          _newDocumentStorageId = null;
          _newDocumentFileName = null;
          _newDocumentFileSize = null;
          _isResubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Application resubmitted! Our team will review within 1–3 business days.'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _resubmitError =
              res.errorMessage ?? 'Resubmission failed. Please try again.';
          _isResubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resubmitError = 'Error: $e';
          _isResubmitting = false;
        });
      }
    }
  }

  // ── Logout ──────────────────────────────────────────────────────────

  void _logout() {
    context.read<AuthBloc>().add(const LogoutEvent());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Enter App (when approved) ────────────────────────────────────────

  void _enterApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigationShell()),
      (_) => false,
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //                               BUILD
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isApproved =
        _verificationStatus == 'approved' || _verificationStatus == 'verified';
    final isRejected = _verificationStatus == 'rejected';
    final isPending = !isApproved && !isRejected;

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar: Logout + Refresh ────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, size: 16,
                        color: AppColors.gray400),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(color: AppColors.gray400, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: _isRefreshing
                        ? null
                        : () => _refreshStatus(),
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.emerald,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded,
                            color: AppColors.emerald, size: 22),
                    tooltip: 'Refresh verification status',
                  ),
                ],
              ),
            ),

            // ── Main Content ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // Logo / Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isApproved
                              ? AppColors.emerald
                              : isRejected
                                  ? AppColors.error
                                  : const Color(0xFFD97706),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isApproved
                                    ? AppColors.emerald
                                    : isRejected
                                        ? AppColors.error
                                        : const Color(0xFFD97706))
                                .withValues(alpha: 0.3),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        isApproved
                            ? Icons.verified_rounded
                            : isRejected
                                ? Icons.gpp_bad_rounded
                                : Icons.pending_actions_rounded,
                        color: isApproved
                            ? AppColors.emerald
                            : isRejected
                                ? AppColors.error
                                : const Color(0xFFD97706),
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      isApproved
                          ? 'Application Approved!'
                          : isRejected
                              ? 'Application Rejected'
                              : 'Application Under Review',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isApproved
                          ? 'Your business has been verified. You now have full access to list properties and vehicles on Vektolux.'
                          : isRejected
                              ? 'Your application could not be approved at this time. Please review the reason below and resubmit with corrected documents.'
                              : 'Our compliance team is reviewing your business credentials. You\'ll receive an update within 1–3 business days.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.gray400,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // ── Status Badge ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isApproved
                                ? AppColors.emerald
                                : isRejected
                                    ? AppColors.error
                                    : const Color(0xFFD97706))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: (isApproved
                                  ? AppColors.emerald
                                  : isRejected
                                      ? AppColors.error
                                      : const Color(0xFFD97706))
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        isApproved
                            ? '✓  APPROVED'
                            : isRejected
                                ? '✕  REJECTED'
                                : '⏳  PENDING REVIEW',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: isApproved
                              ? AppColors.emerald
                              : isRejected
                                  ? AppColors.error
                                  : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Submission Summary Card ───────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Submitted Application',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gray400,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Name',
                            value: widget.user.name,
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.business_rounded,
                            label: 'Business',
                            value: _businessName ?? '—',
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.badge_outlined,
                            label: 'TIN / Reg #',
                            value: _tinNumber ?? '—',
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.description_rounded,
                            label: 'Proof Doc',
                            value: _documentUrl != null && _documentUrl!.isNotEmpty
                                ? 'Uploaded ✓'
                                : 'Not attached',
                            valueColor: _documentUrl != null
                                ? AppColors.emerald
                                : AppColors.gray400,
                          ),
                        ],
                      ),
                    ),

                    // ── Rejection Reason Card ─────────────────────────
                    if (isRejected &&
                        _rejectionReason != null &&
                        _rejectionReason!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B0A0A),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: const Color(0xFF7F1D1D)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    color: AppColors.error, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Rejection Reason',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _rejectionReason!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFFCA5A5),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ── Action Buttons ────────────────────────────────
                    if (isApproved) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _enterApp,
                          icon: const Icon(Icons.arrow_forward_rounded,
                              size: 20),
                          label: const Text(
                            'Enter App',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],

                    if (isRejected) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              setState(() => _showResubmitForm = !_showResubmitForm),
                          icon: Icon(
                            _showResubmitForm
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.upload_file_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _showResubmitForm
                                ? 'Hide Resubmit Form'
                                : 'Resubmit Documents',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),

                      // ── Resubmit Form ─────────────────────────────
                      if (_showResubmitForm) ...[
                        const SizedBox(height: 20),
                        _buildResubmitForm(),
                      ],
                    ],

                    if (isPending) ...[
                      const SizedBox(height: 8),
                      const _PulsingDotRow(),
                      const SizedBox(height: 12),
                      Text(
                        'Auto-refreshing every 30 seconds',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.gray400.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Resubmit Form Widget ────────────────────────────────────────────

  Widget _buildResubmitForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resubmit Verification',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Update your business details and upload corrected documents.',
            style: TextStyle(fontSize: 12, color: AppColors.gray400),
          ),
          const SizedBox(height: 16),

          // Business Name
          TextField(
            controller: _businessNameController,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Business / Company Name',
              labelStyle: const TextStyle(color: AppColors.gray400),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // TIN Number
          TextField(
            controller: _tinController,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'TIN / Business Registration Number',
              labelStyle: const TextStyle(color: AppColors.gray400),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Document Upload
          GestureDetector(
            onTap: _isUploadingDoc ? null : _pickResubmitDocument,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _docError != null
                      ? AppColors.error
                      : _newDocumentStorageId != null
                          ? AppColors.emerald
                          : const Color(0xFF334155),
                ),
              ),
              child: _isUploadingDoc
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.emerald,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Uploading document...',
                            style: TextStyle(
                                color: AppColors.gray400, fontSize: 13)),
                      ],
                    )
                  : _newDocumentStorageId != null
                      ? Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: AppColors.emerald, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_newDocumentFileName ?? "Document"} (${((_newDocumentFileSize ?? 0) / 1024).toStringAsFixed(0)} KB)',
                                style: const TextStyle(
                                    color: AppColors.emerald,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: _pickResubmitDocument,
                              child: const Text('Change',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.attach_file_rounded,
                                color: AppColors.gray400, size: 18),
                            SizedBox(width: 8),
                            Text('Select Proof Document (PDF/JPEG/PNG ≤ 5MB)',
                                style: TextStyle(
                                    color: AppColors.gray400, fontSize: 13)),
                          ],
                        ),
            ),
          ),

          if (_docError != null) ...[
            const SizedBox(height: 6),
            Text(_docError!,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 12)),
          ],

          if (_resubmitError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B0A0A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _resubmitError!,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed:
                  _isResubmitting ? null : _resubmitVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _isResubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Application',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ───────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.gray400),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.gray400,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ?? AppColors.white,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PulsingDotRow extends StatefulWidget {
  const _PulsingDotRow();

  @override
  State<_PulsingDotRow> createState() => _PulsingDotRowState();
}

class _PulsingDotRowState extends State<_PulsingDotRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final delay = i * 0.33;
          final opacity =
              ((_anim.value + delay) % 1.0).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.emerald.withValues(alpha: opacity),
            ),
          );
        }),
      ),
    );
  }
}
