// lib/features/verification/presentation/views/agent_verification_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Agent & Dealer Verification Pipeline & Status Tracker
// Supports 4-step KYC submission wizard, real-time status tracking,
// rejected document re-upload, and subscription badge activation.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/domain/entities/user_entity.dart';

class AgentVerificationScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;
  final String? initialCategory; // 'real_estate_agent' | 'vehicle_dealer' | 'dual'

  const AgentVerificationScreen({
    super.key,
    required this.convexClient,
    required this.currentUser,
    this.initialCategory,
  });

  @override
  State<AgentVerificationScreen> createState() =>
      _AgentVerificationScreenState();
}

class _AgentVerificationScreenState extends State<AgentVerificationScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _verificationData;
  bool _forceWizardMode = false;

  // ── Wizard State ──────────────────────────────────────────────────
  int _currentStep = 0; // 0: Business Info, 1: Personal KYC, 2: Business Docs, 3: Review
  final _formKey = GlobalKey<FormState>();

  // Step 1 Controllers
  late String _selectedRoleCategory;
  final _businessNameController = TextEditingController();
  final _tinController = TextEditingController();
  final _officeAddressController = TextEditingController();
  final _officeCityController = TextEditingController(text: 'Freetown');
  final _publicPhoneController = TextEditingController();
  final _publicWhatsAppController = TextEditingController();

  // Step 2 Uploads (Personal KYC)
  String _idDocType = 'National ID';
  Uint8List? _idFrontBytes;
  String? _idFrontStorageId;
  String? _idFrontUrl;

  Uint8List? _idBackBytes;
  String? _idBackStorageId;
  String? _idBackUrl;

  Uint8List? _selfieBytes;
  String? _selfieStorageId;
  String? _selfieUrl;

  // Step 3 Uploads (Business Verification)
  Uint8List? _businessRegBytes;
  String? _businessRegStorageId;
  String? _businessRegUrl;

  Uint8List? _officeProofBytes;
  String? _officeProofStorageId;
  String? _officeProofUrl;

  // Step 4 Declaration
  bool _agreedToTerms = false;
  bool _isSubmitting = false;

  // Re-upload in-progress tracker
  final Map<String, bool> _reuploadingDocIds = {};

  @override
  void initState() {
    super.initState();
    _selectedRoleCategory = widget.initialCategory ??
        (widget.currentUser.role == UserRole.merchant
            ? 'vehicle_dealer'
            : 'real_estate_agent');

    // Pre-populate phone if user entity has one
    final cleanPhone = widget.currentUser.phone.replaceAll('+232', '').trim();
    if (cleanPhone.isNotEmpty) {
      _publicPhoneController.text = cleanPhone;
      _publicWhatsAppController.text = cleanPhone;
    }

    _loadStatus();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _tinController.dispose();
    _officeAddressController.dispose();
    _officeCityController.dispose();
    _publicPhoneController.dispose();
    _publicWhatsAppController.dispose();
    super.dispose();
  }

  // ── Load Remote Status ────────────────────────────────────────────
  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.convexClient.query(
        'agentVerification:getVerificationStatus',
        args: {'userId': widget.currentUser.id},
      );

      if (mounted) {
        if (res.success && res.value != null) {
          final data = Map<String, dynamic>.from(res.value as Map);
          setState(() {
            _verificationData = data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _verificationData = {'hasApplied': false};
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load verification status: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ── Document Picking & Cloud Upload ───────────────────────────────
  Future<void> _pickAndUploadDocument({
    required String docKey,
    required ImageSource source,
    Function(Uint8List bytes, String storageId, String url)? onComplete,
  }) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (file == null) return;
      final bytes = await file.readAsBytes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Encrypting and uploading document...'),
          duration: Duration(seconds: 2),
        ),
      );

      // Upload binary to Convex Storage
      final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: widget.convexClient,
        imageBytes: bytes,
        contentType: 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          switch (docKey) {
            case 'id_front':
              _idFrontBytes = bytes;
              _idFrontStorageId = uploadRes.storageId;
              _idFrontUrl = uploadRes.publicUrl;
              break;
            case 'id_back':
              _idBackBytes = bytes;
              _idBackStorageId = uploadRes.storageId;
              _idBackUrl = uploadRes.publicUrl;
              break;
            case 'selfie':
              _selfieBytes = bytes;
              _selfieStorageId = uploadRes.storageId;
              _selfieUrl = uploadRes.publicUrl;
              break;
            case 'business_reg':
              _businessRegBytes = bytes;
              _businessRegStorageId = uploadRes.storageId;
              _businessRegUrl = uploadRes.publicUrl;
              break;
            case 'office_proof':
              _officeProofBytes = bytes;
              _officeProofStorageId = uploadRes.storageId;
              _officeProofUrl = uploadRes.publicUrl;
              break;
          }
        });

        if (onComplete != null) {
          onComplete(bytes, uploadRes.storageId, uploadRes.publicUrl);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document uploaded successfully.'),
            backgroundColor: AppColors.emeraldDark,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Submit Verification Wizard ────────────────────────────────────
  Future<void> _submitApplication() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm the legal declaration before submitting.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final documentsPayload = <Map<String, dynamic>>[];

      if (_idFrontUrl != null) {
        documentsPayload.add({
          'documentType': 'government_id_front',
          'fileUrl': _idFrontUrl!,
          'fileStorageId': _idFrontStorageId,
          'fileMimeType': 'image/jpeg',
          'fileSizeBytes': _idFrontBytes?.lengthInBytes ?? 102400,
        });
      }
      if (_idBackUrl != null) {
        documentsPayload.add({
          'documentType': 'government_id_back',
          'fileUrl': _idBackUrl!,
          'fileStorageId': _idBackStorageId,
          'fileMimeType': 'image/jpeg',
          'fileSizeBytes': _idBackBytes?.lengthInBytes ?? 102400,
        });
      }
      if (_selfieUrl != null) {
        documentsPayload.add({
          'documentType': 'live_selfie',
          'fileUrl': _selfieUrl!,
          'fileStorageId': _selfieStorageId,
          'fileMimeType': 'image/jpeg',
          'fileSizeBytes': _selfieBytes?.lengthInBytes ?? 102400,
        });
      }
      if (_businessRegUrl != null) {
        documentsPayload.add({
          'documentType': 'business_registration',
          'fileUrl': _businessRegUrl!,
          'fileStorageId': _businessRegStorageId,
          'fileMimeType': 'image/jpeg',
          'fileSizeBytes': _businessRegBytes?.lengthInBytes ?? 102400,
        });
      }
      if (_officeProofUrl != null) {
        documentsPayload.add({
          'documentType': 'office_utility_bill',
          'fileUrl': _officeProofUrl!,
          'fileStorageId': _officeProofStorageId,
          'fileMimeType': 'image/jpeg',
          'fileSizeBytes': _officeProofBytes?.lengthInBytes ?? 102400,
        });
      }

      final res = await widget.convexClient.mutation(
        'agentVerification:submitVerification',
        args: {
          'userId': widget.currentUser.id,
          'roleCategory': _selectedRoleCategory,
          'businessName': _businessNameController.text.trim(),
          'tinNumber': _tinController.text.trim().isEmpty
              ? null
              : _tinController.text.trim(),
          'officeAddress': _officeAddressController.text.trim(),
          'officeCity': _officeCityController.text.trim(),
          'publicPhone': '+232 ${_publicPhoneController.text.trim()}',
          'publicWhatsApp': _publicWhatsAppController.text.trim().isEmpty
              ? null
              : '+232 ${_publicWhatsAppController.text.trim()}',
          'documents': documentsPayload,
        },
      );

      if (res.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Application submitted! Compliance review turnaround is 4-24 hours.'),
              backgroundColor: AppColors.emeraldDark,
              duration: Duration(seconds: 4),
            ),
          );
          _forceWizardMode = false;
          await _loadStatus();
        }
      } else {
        throw Exception(res.errorMessage ?? 'Submission failed.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Re-upload Rejected Document ───────────────────────────────────
  Future<void> _handleReupload(String documentId, String docType) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );

    if (file == null) return;
    final bytes = await file.readAsBytes();

    setState(() => _reuploadingDocIds[documentId] = true);

    try {
      final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: widget.convexClient,
        imageBytes: bytes,
        contentType: 'image/jpeg',
      );

      final res = await widget.convexClient.mutation(
        'agentVerification:reuploadDocument',
        args: {
          'documentId': documentId,
          'fileUrl': uploadRes.publicUrl,
          'fileStorageId': uploadRes.storageId,
          'fileMimeType': 'image/jpeg',
          'fileSizeBytes': bytes.lengthInBytes,
        },
      );

      if (res.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Replacement document submitted for review.'),
              backgroundColor: AppColors.emeraldDark,
            ),
          );
          await _loadStatus();
        }
      } else {
        throw Exception(res.errorMessage ?? 'Re-upload failed.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error re-uploading document: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reuploadingDocIds.remove(documentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasApplied = _verificationData?['hasApplied'] == true;
    final showStatusHub = hasApplied && !_forceWizardMode;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          showStatusHub ? 'Verification Hub' : 'Agent & Dealer Verification',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: AppColors.obsidian,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.emeraldDark),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 48),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        VxButton(
                          label: 'Try Again',
                          onPressed: _loadStatus,
                          variant: VxButtonVariant.primary,
                        ),
                      ],
                    ),
                  ),
                )
              : showStatusHub
                  ? _buildStatusTrackerHub()
                  : _buildWizardForm(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    STATUS TRACKER HUB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStatusTrackerHub() {
    final status = _verificationData?['status'] as String? ?? 'pending_review';
    final businessName = _verificationData?['businessName'] as String? ?? 'Your Business';
    final roleCat = _verificationData?['roleCategory'] as String? ?? _selectedRoleCategory;
    final submittedAt = _verificationData?['submittedAt'] as int?;
    final reviewerNotes = _verificationData?['reviewerNotes'] as String?;
    final documents = (_verificationData?['documents'] as List?) ?? [];

    Color statusColor;
    String statusTitle;
    IconData statusIcon;

    switch (status) {
      case 'active':
        statusColor = AppColors.emeraldDark;
        statusTitle = 'Verified Active';
        statusIcon = Icons.verified_rounded;
        break;
      case 'approved_pending_payment':
        statusColor = const Color(0xFF0284C7);
        statusTitle = 'Approved — Action: Activate Subscription';
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'action_required':
        statusColor = const Color(0xFFEA580C);
        statusTitle = 'Action Required: Re-upload Documents';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        statusTitle = 'Application Rejected';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'pending_review':
      default:
        statusColor = const Color(0xFFD97706);
        statusTitle = 'Under Review (4-24h turnaround)';
        statusIcon = Icons.schedule_rounded;
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status Banner Card ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            businessName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatRole(roleCat),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (submittedAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Submitted on ${DateTime.fromMillisecondsSinceEpoch(submittedAt).toLocal().toString().split('.')[0]}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Specific Notice Boxes ─────────────────────────────────
          if (status == 'action_required' && reviewerNotes != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFEA580C), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Compliance Review Feedback',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reviewerNotes,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7C2D12),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (status == 'approved_pending_payment') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified, color: AppColors.emeraldDark, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'KYC Credentials Verified!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your business credentials and identity have passed legal review. '
                    'Activate your vendor subscription to unlock direct phone calls & WhatsApp chats from buyers, plus the Green Verified Badge.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF166534),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: VxButton(
                      label: 'Activate Verified Badge',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please complete subscription payment in the Vendor Management screen.',
                            ),
                          ),
                        );
                      },
                      variant: VxButtonVariant.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (status == 'active') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.emeraldDark, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Direct Lead Routing Active: Buyers see your direct phone number and WhatsApp button on all listings.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Submitted Documents List ─────────────────────────────
          const SizedBox(height: 24),
          const Text(
            'Submitted Documents',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 12),

          if (documents.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'No documents attached to this application.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...documents.map((doc) {
              final docMap = Map<String, dynamic>.from(doc as Map);
              final docId = docMap['id'] as String;
              final docType = docMap['documentType'] as String? ?? 'document';
              final docStatus = docMap['status'] as String? ?? 'pending';
              final rejectionComment = docMap['rejectionComment'] as String?;
              final isRejected = docStatus == 'rejected';
              final isUploading = _reuploadingDocIds[docId] == true;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isRejected ? const Color(0xFFFCA5A5) : AppColors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isRejected
                              ? Icons.cancel_outlined
                              : (docStatus == 'approved'
                                  ? Icons.check_circle_outline
                                  : Icons.description_outlined),
                          color: isRejected
                              ? AppColors.error
                              : (docStatus == 'approved'
                                  ? AppColors.emeraldDark
                                  : AppColors.textSecondary),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDocType(docType),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              Text(
                                'Status: ${docStatus.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isRejected
                                      ? AppColors.error
                                      : (docStatus == 'approved'
                                          ? AppColors.emeraldDark
                                          : const Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isRejected)
                          isUploading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : VxButton(
                                  label: 'Re-upload',
                                  variant: VxButtonVariant.outlined,
                                  onPressed: () => _handleReupload(docId, docType),
                                ),
                      ],
                    ),
                    if (isRejected && rejectionComment != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Issue: $rejectionComment',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),

          // ── Option to submit fresh application if rejected ────────
          if (status == 'rejected') ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: VxButton(
                label: 'Start New Application',
                variant: VxButtonVariant.primary,
                onPressed: () => setState(() => _forceWizardMode = true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    4-STEP SUBMISSION WIZARD
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildWizardForm() {
    return Column(
      children: [
        // ── Step Progress Indicator ─────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              _buildStepDot(0, 'Business'),
              _buildStepLine(0),
              _buildStepDot(1, 'Identity'),
              _buildStepLine(1),
              _buildStepDot(2, 'License'),
              _buildStepLine(2),
              _buildStepDot(3, 'Review'),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Step Content ────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: switch (_currentStep) {
                0 => _buildStep1BusinessInfo(),
                1 => _buildStep2IdentityKyc(),
                2 => _buildStep3BusinessDocuments(),
                3 => _buildStep4ReviewAndSubmit(),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ),

        // ── Wizard Navigation Controls ──────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: VxButton(
                    label: 'Back',
                    variant: VxButtonVariant.outlined,
                    onPressed: () => setState(() => _currentStep--),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: _currentStep < 3
                    ? VxButton(
                        label: 'Continue',
                        variant: VxButtonVariant.primary,
                        onPressed: _validateAndProceed,
                      )
                    : VxButton(
                        label: _isSubmitting
                            ? 'Submitting...'
                            : 'Submit Verification',
                        variant: VxButtonVariant.primary,
                        onPressed: _isSubmitting ? null : _submitApplication,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _validateAndProceed() {
    if (_currentStep == 0) {
      if (_formKey.currentState?.validate() == true) {
        setState(() => _currentStep++);
      }
    } else if (_currentStep == 1) {
      if (_idFrontUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload front side of your Government ID.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (_selfieUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please take a clear selfie headshot.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      setState(() => _currentStep++);
    } else if (_currentStep == 2) {
      if (_businessRegUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload your Business Registration or License.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      setState(() => _currentStep++);
    }
  }

  // ── Step 1: Business Profile ──────────────────────────────────────
  Widget _buildStep1BusinessInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operating Profile & Business Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose your operating license model and public contact details.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Role Category Selector
        const Text(
          'License Category *',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRoleRadio(
              title: 'Real Estate',
              value: 'real_estate_agent',
              icon: Icons.apartment_rounded,
            ),
            const SizedBox(width: 8),
            _buildRoleRadio(
              title: 'Vehicle Dealer',
              value: 'vehicle_dealer',
              icon: Icons.directions_car_rounded,
            ),
            const SizedBox(width: 8),
            _buildRoleRadio(
              title: 'Dual Operator',
              value: 'dual',
              icon: Icons.hub_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Business Name
        TextFormField(
          controller: _businessNameController,
          decoration: const InputDecoration(
            labelText: 'Business / Agency Name *',
            hintText: 'e.g. Sierra Prime Properties Ltd',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Business name is required' : null,
        ),
        const SizedBox(height: 16),

        // TIN Number
        TextFormField(
          controller: _tinController,
          decoration: const InputDecoration(
            labelText: 'Tax Identification Number (TIN)',
            hintText: 'e.g. TIN-1002934-8',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Office Address
        TextFormField(
          controller: _officeAddressController,
          decoration: const InputDecoration(
            labelText: 'Physical Office Address *',
            hintText: 'e.g. 24 Siaka Stevens Street, Suite 3B',
            border: OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Office address is required'
              : null,
        ),
        const SizedBox(height: 16),

        // City
        TextFormField(
          controller: _officeCityController,
          decoration: const InputDecoration(
            labelText: 'City *',
            hintText: 'e.g. Freetown',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'City is required' : null,
        ),
        const SizedBox(height: 16),

        // Public Contact Phone
        TextFormField(
          controller: _publicPhoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Public Phone for Leads *',
            prefixText: '+232 ',
            hintText: '76 000 000',
            border: OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Lead phone number is required'
              : null,
        ),
        const SizedBox(height: 16),

        // Public WhatsApp
        TextFormField(
          controller: _publicWhatsAppController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'WhatsApp Business Number (Optional)',
            prefixText: '+232 ',
            hintText: '77 000 000',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Personal KYC & Liveness ───────────────────────────────
  Widget _buildStep2IdentityKyc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Identity & Biometric Photo',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload official government-issued ID and a direct selfie to confirm identity.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // ID Document Type Dropdown
        DropdownButtonFormField<String>(
          value: _idDocType,
          decoration: const InputDecoration(
            labelText: 'ID Document Type *',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'National ID', child: Text('National ID Card')),
            DropdownMenuItem(value: 'Passport', child: Text('International Passport')),
            DropdownMenuItem(value: 'Driver License', child: Text("Driver's License")),
          ],
          onChanged: (v) => setState(() => _idDocType = v ?? 'National ID'),
        ),
        const SizedBox(height: 20),

        // ID Front Upload
        _buildUploadCard(
          title: 'Front Side of ID *',
          subtitle: 'Ensure all text, photo, and national number are sharp and glare-free.',
          docKey: 'id_front',
          hasUploaded: _idFrontUrl != null,
          bytes: _idFrontBytes,
        ),
        const SizedBox(height: 16),

        // ID Back Upload
        _buildUploadCard(
          title: 'Back Side of ID (Optional)',
          subtitle: 'Required for National ID cards with barcode or address on reverse.',
          docKey: 'id_back',
          hasUploaded: _idBackUrl != null,
          bytes: _idBackBytes,
        ),
        const SizedBox(height: 16),

        // Live Selfie Upload
        _buildUploadCard(
          title: 'Live Selfie Headshot *',
          subtitle: 'Take a clear portrait looking directly at the camera in good lighting.',
          docKey: 'selfie',
          hasUploaded: _selfieUrl != null,
          bytes: _selfieBytes,
          forceCamera: true,
        ),
      ],
    );
  }

  // ── Step 3: Business Registration & Proof ─────────────────────────
  Widget _buildStep3BusinessDocuments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Registration & Office Proof',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Provide official business incorporation or dealership permit and proof of address.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Certificate of Incorporation
        _buildUploadCard(
          title: 'Business Registration / License *',
          subtitle: 'Certificate of Incorporation, Business Registration or Agency License.',
          docKey: 'business_reg',
          hasUploaded: _businessRegUrl != null,
          bytes: _businessRegBytes,
        ),
        const SizedBox(height: 16),

        // Office Proof
        _buildUploadCard(
          title: 'Office Address Proof (Optional)',
          subtitle: 'Recent commercial utility bill, tenancy lease agreement, or tax receipt.',
          docKey: 'office_proof',
          hasUploaded: _officeProofUrl != null,
          bytes: _officeProofBytes,
        ),
      ],
    );
  }

  // ── Step 4: Review & Legal Declaration ────────────────────────────
  Widget _buildStep4ReviewAndSubmit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review Application Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Review all submitted information and documents before final submission.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildReviewRow('Category', _formatRole(_selectedRoleCategory)),
              _buildReviewRow('Business Name', _businessNameController.text),
              _buildReviewRow('TIN', _tinController.text.isEmpty ? 'Not Provided' : _tinController.text),
              _buildReviewRow('Address', '${_officeAddressController.text}, ${_officeCityController.text}'),
              _buildReviewRow('Public Phone', '+232 ${_publicPhoneController.text}'),
              if (_publicWhatsAppController.text.isNotEmpty)
                _buildReviewRow('WhatsApp', '+232 ${_publicWhatsAppController.text}'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Documents checklist
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Attached Credentials',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _buildDocReviewItem('Government ID (Front)', _idFrontUrl != null),
              _buildDocReviewItem('Government ID (Back)', _idBackUrl != null),
              _buildDocReviewItem('Live Selfie Headshot', _selfieUrl != null),
              _buildDocReviewItem('Business Registration Certificate', _businessRegUrl != null),
              _buildDocReviewItem('Office Address Proof', _officeProofUrl != null),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Terms Checkbox
        CheckboxListTile(
          value: _agreedToTerms,
          activeColor: AppColors.emeraldDark,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I certify under penalty of perjury that all uploaded documents and business credentials are authentic, genuine, and legally owned by the applicant.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
          onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
        ),
      ],
    );
  }

  // ── Supporting Widget Helpers ─────────────────────────────────────
  Widget _buildRoleRadio({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedRoleCategory == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRoleCategory = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.emeraldDark : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.emeraldDark : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard({
    required String title,
    required String subtitle,
    required String docKey,
    required bool hasUploaded,
    Uint8List? bytes,
    bool forceCamera = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUploaded ? AppColors.emeraldDark : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasUploaded ? Icons.check_circle : Icons.upload_file_outlined,
                color: hasUploaded ? AppColors.emeraldDark : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              if (hasUploaded)
                const Text(
                  'Uploaded',
                  style: TextStyle(
                    color: AppColors.emeraldDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (!forceCamera)
                Expanded(
                  child: VxButton(
                    label: hasUploaded ? 'Change File' : 'Pick Gallery',
                    variant: VxButtonVariant.outlined,
                    onPressed: () => _pickAndUploadDocument(
                      docKey: docKey,
                      source: ImageSource.gallery,
                    ),
                  ),
                ),
              if (!forceCamera) const SizedBox(width: 10),
              Expanded(
                child: VxButton(
                  label: forceCamera ? 'Open Camera' : 'Camera',
                  variant: forceCamera
                      ? (hasUploaded
                          ? VxButtonVariant.outlined
                          : VxButtonVariant.primary)
                      : VxButtonVariant.outlined,
                  onPressed: () => _pickAndUploadDocument(
                    docKey: docKey,
                    source: ImageSource.camera,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepDot(int stepIndex, String label) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDone
                ? AppColors.emeraldDark
                : (isActive ? AppColors.obsidian : const Color(0xFFE2E8F0)),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppColors.obsidian : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int afterStep) {
    final isDone = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16),
        color: isDone ? AppColors.emeraldDark : const Color(0xFFE2E8F0),
      ),
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.obsidian,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocReviewItem(String title, bool isProvided) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isProvided ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isProvided ? AppColors.emeraldDark : AppColors.textDisabled,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isProvided ? AppColors.obsidian : AppColors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRole(String role) {
    switch (role) {
      case 'real_estate_agent':
        return 'Real Estate Agent';
      case 'vehicle_dealer':
        return 'Vehicle Dealership';
      case 'dual':
        return 'Dual Operator (Real Estate & Auto)';
      default:
        return role;
    }
  }

  String _formatDocType(String type) {
    switch (type) {
      case 'government_id_front':
        return 'Government ID (Front)';
      case 'government_id_back':
        return 'Government ID (Back)';
      case 'live_selfie':
        return 'Live Selfie Headshot';
      case 'business_registration':
        return 'Business Registration / License';
      case 'office_utility_bill':
        return 'Proof of Office Address';
      default:
        return type.replaceAll('_', ' ');
    }
  }
}
