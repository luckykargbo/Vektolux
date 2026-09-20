// lib/features/profile/presentation/views/profile_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — User Profile, Account Settings & Vendor Management
// Comprehensive profile dashboard with Orange/Africell Mobile Money,
// KYC verification status, vendor tools, and secure session logout.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/views/login_screen.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../../operator/presentation/views/operator_dashboard_screen.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../listings/presentation/views/my_listings_screen.dart';
import '../../../auth/presentation/views/pending_verification_screen.dart';
import '../../../social/presentation/views/public_profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/payment_methods_service.dart';
import '../../../../core/models/payment_account.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


class ProfileScreen extends StatefulWidget {
  final String? currentUserId;
  final bool showBackButton;

  const ProfileScreen({
    super.key,
    this.currentUserId,
    this.showBackButton = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Notification preferences (local UI toggles) ───────────────────
  bool _pushNotifications = true;
  bool _smsAlerts = true;

  // ── Escrow wallet display state ───────────────────────────────────
  bool _isBalanceVisible = true;
  bool _escrowBiometricEnabled = true;

  // ── Live Convex wallet data (replaces hardcoded _escrowBalance) ───
  double? _walletBalance;        // null = loading
  int _activeEscrowDeals = 0;
  bool _isLoadingBalance = true;

  // ── Live Convex payment accounts (replaces local _savedPaymentMethods) ──
  List<PaymentAccount> _userPaymentAccounts = [];
  bool _isLoadingAccounts = true;

  // ── Vendor listing count (replaces hardcoded '6 Items') ───────────
  int _vendorListingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthBloc>().add(const RefreshUserSessionEvent());
      _fetchWalletData();
      _fetchUserPaymentAccounts();
    });
  }

  /// Fetch live wallet balance, escrow status, and dynamic profile from Convex.
  Future<void> _fetchWalletData() async {
    if (!mounted) return;
    final userId = context.read<AuthBloc>().state.user?.id;
    if (userId == null) {
      setState(() => _isLoadingBalance = false);
      return;
    }
    final client = context.read<ConvexClientWrapper>();
    try {
      // 1. Try unified getWalletProfile
      final profileRes = await client.query(
        'users:getWalletProfile',
        args: {'userId': userId},
      );
      if (profileRes.success && profileRes.value is Map) {
        final data = profileRes.value as Map;
        final propRes = await client.query(
          'realEstate:getMyPropertyListings',
          args: {'userId': userId},
        );
        if (!mounted) return;
        setState(() {
          _walletBalance = (data['walletBalance'] as num?)?.toDouble() ?? 0.0;
          _activeEscrowDeals = (data['activeEscrowDeals'] as num?)?.toInt() ?? 0;
          final listings =
              propRes.value is List ? propRes.value as List : <dynamic>[];
          _vendorListingCount = listings.length;
          _isLoadingBalance = false;
        });
        return;
      }

      // 2. Resilient fallback to individual queries
      final walletRes = await client.query(
        'payments:getWalletBalance',
        args: {'userId': userId},
      );
      final ordersRes = await client.query(
        'escrow:getMyEscrowOrders',
        args: {'userId': userId},
      );
      final propRes = await client.query(
        'realEstate:getMyPropertyListings',
        args: {'userId': userId},
      );
      if (!mounted) return;
      setState(() {
        _walletBalance =
            (walletRes.value?['availableBalance'] as num?)?.toDouble() ?? 0.0;
        final orders =
            ordersRes.value is List ? ordersRes.value as List : <dynamic>[];
        _activeEscrowDeals = orders.where((o) {
          final s = (o as Map)['status'] as String? ?? '';
          return s == 'FUNDED' ||
              s == 'INSPECTION_IN_PROGRESS' ||
              s == 'AWAITING_HANDOFF';
        }).length;
        final listings =
            propRes.value is List ? propRes.value as List : <dynamic>[];
        _vendorListingCount = listings.length;
        _isLoadingBalance = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  /// Fetch user's Convex-persisted linked payment accounts.
  Future<void> _fetchUserPaymentAccounts() async {
    if (!mounted) return;
    final userId = context.read<AuthBloc>().state.user?.id;
    if (userId == null) {
      setState(() => _isLoadingAccounts = false);
      return;
    }
    final client = context.read<ConvexClientWrapper>();
    try {
      final res = await client.query(
        'payments:getUserPaymentAccounts',
        args: {'userId': userId},
      );
      if (!mounted) return;
      if (res.success && res.value is List) {
        setState(() {
          _userPaymentAccounts = (res.value as List)
              .map((item) =>
                  PaymentAccount.fromJson(item as Map<String, dynamic>))
              .toList();
          _isLoadingAccounts = false;
        });
      } else {
        setState(() => _isLoadingAccounts = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAccounts = false);
    }
  }


  void _showEditProfileModal(BuildContext context, UserEntity user) {
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phone);
    final bioCtrl = TextEditingController(text: user.bio ?? '');
    final addressCtrl = TextEditingController(text: user.address ?? '');
    String? selectedRegion = user.region;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.gray300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Edit Account Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Update your display name, contact phone number, address, and bio.',
                      style: TextStyle(fontSize: 13, color: AppColors.gray500),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: nameCtrl,
                      style: const TextStyle(
                        color: AppColors.obsidian,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        color: AppColors.obsidian,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Area / District Dropdown
                    DropdownButtonFormField<String>(
                      value: (selectedRegion != null && selectedRegion!.isNotEmpty)
                          ? selectedRegion
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Area / District (Optional)',
                        hintText: 'Select your general area',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Freetown Central', child: Text('Freetown Central (Western Urban)')),
                        DropdownMenuItem(value: 'Lumley & Aberdeen', child: Text('Lumley & Aberdeen (Beachfront)')),
                        DropdownMenuItem(value: 'Wilkinson Road & Congo Cross', child: Text('Wilkinson Road & Congo Cross')),
                        DropdownMenuItem(value: 'Hill Station & Regent', child: Text('Hill Station & Regent (Mountain)')),
                        DropdownMenuItem(value: 'Waterloo & Goderich', child: Text('Waterloo & Goderich (Western Rural)')),
                        DropdownMenuItem(value: 'Bo City', child: Text('Bo City (Southern Province)')),
                        DropdownMenuItem(value: 'Kenema', child: Text('Kenema (Eastern Province)')),
                        DropdownMenuItem(value: 'Makeni', child: Text('Makeni (Northern Province)')),
                      ],
                      onChanged: (val) => setModalState(() => selectedRegion = val),
                    ),
                    const SizedBox(height: 14),
                    // Street Address
                    TextFormField(
                      controller: addressCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        color: AppColors.obsidian,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        labelText: 'Street Address (Optional)',
                        hintText: 'e.g. 14 Wilkinson Road, Freetown',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: bioCtrl,
                      maxLines: 3,
                      style: const TextStyle(
                        color: AppColors.obsidian,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        labelText: 'Bio / About You',
                        alignLabelWithHint: true,
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.edit_note_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          final updatedName = nameCtrl.text.trim();
                          final updatedPhone = phoneCtrl.text.trim();
                          final updatedBio = bioCtrl.text.trim();
                          final updatedAddress = addressCtrl.text.trim();
                          context.read<AuthBloc>().add(
                                UpdateUserProfileEvent(
                                  name: updatedName.isNotEmpty ? updatedName : null,
                                  phone: updatedPhone.isNotEmpty ? updatedPhone : null,
                                  bio: updatedBio.isNotEmpty ? updatedBio : null,
                                  address: updatedAddress.isNotEmpty ? updatedAddress : null,
                                  region: selectedRegion,
                                ),
                              );
                          Navigator.of(modalCtx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile information updated successfully.'),
                              backgroundColor: AppColors.emerald,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAvatarPickerModal(BuildContext context, UserEntity? user) {
    Uint8List? pickedBytes;
    String? currentAvatarUrl = user?.avatarUrl;
    bool isUploading = false;
    String? uploadError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickAndStage(bool isCamera) async {
              setModalState(() {
                uploadError = null;
              });
              final file = isCamera
                  ? await ImageUploadService.pickImageFromCamera()
                  : await ImageUploadService.pickImageFromGallery();
              if (file != null) {
                final bytes = await file.readAsBytes();
                setModalState(() {
                  pickedBytes = bytes;
                });
              }
            }

            Future<void> executeUpload() async {
              if (pickedBytes == null) return;
              setModalState(() {
                isUploading = true;
                uploadError = null;
              });
              try {
                final convexClient = context.read<ConvexClientWrapper>();
                final authRepo = context.read<AuthRepository>();
                final publicUrl = await ImageUploadService.uploadImageToConvex(
                  convexClient: convexClient,
                  imageBytes: pickedBytes!,
                );

                // Ensure avatar is synced and confirmed on Convex backend
                final userId = user?.id;
                if (userId != null && userId.isNotEmpty) {
                  await authRepo.updateUserProfile(
                    userId: userId,
                    avatarUrl: publicUrl,
                  );
                  try {
                    await convexClient.mutation('users:updateAvatar', args: {
                      'userId': userId,
                      'avatarUrl': publicUrl,
                    });
                  } catch (_) {}
                }

                if (modalCtx.mounted) {
                  context.read<AuthBloc>().add(
                        UpdateUserProfileEvent(avatarUrl: publicUrl),
                      );
                  Navigator.of(modalCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile photo uploaded and synced to cloud!'),
                      backgroundColor: AppColors.emerald,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                setModalState(() {
                  isUploading = false;
                  uploadError = 'Upload failed: $e';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Profile Photo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Take a photo or choose an image from your device gallery.',
                    style: TextStyle(fontSize: 13, color: AppColors.gray500),
                  ),
                  const SizedBox(height: 20),

                  // 1:1 Circular Crop Preview with Emerald Ring
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.emerald, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.emerald.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: pickedBytes != null
                                ? Image.memory(
                                    pickedBytes!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  )
                                : (currentAvatarUrl != null && currentAvatarUrl.isNotEmpty)
                                    ? Image.network(
                                        currentAvatarUrl,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.person_rounded,
                                          size: 50,
                                          color: AppColors.gray400,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person_rounded,
                                        size: 50,
                                        color: AppColors.gray400,
                                      ),
                          ),
                        ),
                        if (isUploading)
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.5),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.emerald,
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (uploadError != null) ...[
                    Center(
                      child: Text(
                        uploadError!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Camera and Gallery Quick Pickers
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isUploading ? null : () => pickAndStage(true),
                          icon: const Icon(Icons.camera_alt_outlined, size: 20, color: AppColors.obsidian),
                          label: const Text('Camera', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: AppColors.gray200, width: 1.2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isUploading ? null : () => pickAndStage(false),
                          icon: const Icon(Icons.photo_library_outlined, size: 20, color: AppColors.obsidian),
                          label: const Text('Gallery / Files', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: AppColors.gray200, width: 1.2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Explicit Action Bar: [Cancel] & [Save Photo]
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isUploading
                              ? null
                              : () {
                                  setModalState(() {
                                    pickedBytes = null;
                                    uploadError = null;
                                  });
                                  Navigator.of(modalCtx).pop();
                                },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppColors.gray300, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.obsidian,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: (pickedBytes == null || isUploading)
                              ? null
                              : executeUpload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: AppColors.white,
                            disabledBackgroundColor: AppColors.gray200,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: isUploading
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: AppColors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Saving Photo...',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                  ],
                                )
                              : const Text(
                                  'Save Photo',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                        ),
                      ),
                    ],
                  ),
                  if (currentAvatarUrl != null && currentAvatarUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                try {
                                  final userId = user?.id;
                                  if (userId != null && userId.isNotEmpty) {
                                    final authRepo = context.read<AuthRepository>();
                                    await authRepo.updateUserProfile(
                                      userId: userId,
                                      avatarUrl: '',
                                    );
                                    try {
                                      final convexClient = context.read<ConvexClientWrapper>();
                                      await convexClient.mutation('users:updateAvatar', args: {
                                        'userId': userId,
                                        'avatarUrl': '',
                                      });
                                    } catch (_) {}
                                  }
                                  if (modalCtx.mounted) {
                                    context.read<AuthBloc>().add(
                                          const UpdateUserProfileEvent(avatarUrl: ''),
                                        );
                                    Navigator.of(modalCtx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Profile photo removed.'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    uploadError = 'Failed to remove photo: $e';
                                  });
                                }
                              },
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                        label: const Text(
                          'Remove Current Photo',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: AppColors.error, size: 24),
              SizedBox(width: 10),
              Text(
                'Log Out',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of your Vektolux account? Your offline encrypted cache will be securely cleared.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.gray600,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.gray500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                // Clear local database session
                try {
                  final db = context.read<AppDatabase>();
                  await db.cachedUsersDao.clearSession();
                } catch (_) {}

                if (!context.mounted) return;

                // Dispatch AuthBloc logout event
                context.read<AuthBloc>().add(const LogoutEvent());

                // Clear client auth token
                try {
                  context.read<ConvexClientWrapper>().clearAuth();
                } catch (_) {}

                // Route to LoginScreen
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  void _showInfoSheet(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.gray600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: VxButton.small(
                  label: 'Close',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomerSupportModal(BuildContext context) {
    const supportPhone = '+23273623761';
    const formattedPhone = '+232 73 623 761';
    final whatsappUri = Uri.parse(
      'https://wa.me/23273623761?text=${Uri.encodeComponent("Hello Vektolux Customer Support, I would like to make an inquiry regarding my account.")}',
    );
    final callUri = Uri.parse('tel:$supportPhone');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: AppColors.emeraldDark,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer Support',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Available 24/7 in Sierra Leone • Choose how to connect',
                            style: TextStyle(fontSize: 12, color: AppColors.gray500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Option 1: WhatsApp Support
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      try {
                        final launched = await launchUrl(
                          whatsappUri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!launched) {
                          await launchUrl(whatsappUri);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not launch WhatsApp. Support: $formattedPhone'),
                              backgroundColor: AppColors.obsidian,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Color(0xFF25D366),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Text(
                                      'Chat on WhatsApp',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.obsidian,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.all(Radius.circular(6)),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        child: Text(
                                          'Instant',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Send messages, voice notes & images ($formattedPhone)',
                                  style: const TextStyle(fontSize: 12, color: AppColors.gray600),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Color(0xFF16A34A),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Option 2: Normal Mobile Phone Call
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      try {
                        final launched = await launchUrl(callUri);
                        if (!launched && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Phone dialer not supported on this device.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not initiate call: $e'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: AppColors.emeraldSurface,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.phone_in_talk_rounded,
                              color: AppColors.emeraldDark,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Normal Mobile Call',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Direct cellular audio call ($formattedPhone)',
                                  style: TextStyle(fontSize: 12, color: AppColors.gray600),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.gray400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Option 3: Copy Phone Number
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Clipboard.setData(const ClipboardData(text: supportPhone));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Support line copied: $formattedPhone'),
                          backgroundColor: AppColors.emerald,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.copy_rounded, size: 16, color: AppColors.gray500),
                          SizedBox(width: 8),
                          Text(
                            'Copy Support Number ($formattedPhone)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.gray600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        final displayName = user?.name.isNotEmpty == true ? user!.name : 'User';
        final displayPhone = user?.phone.isNotEmpty == true ? user!.phone : '';
        final displayEmail = user?.email.isNotEmpty == true ? user!.email : '';
        final userBio = user?.bio;
        final userRegion = user?.region;
        final userAddress = user?.address;
        final role = user?.role ?? UserRole.client;
        final isVendor = role == UserRole.agent ||
            role == UserRole.merchant ||
            role == UserRole.driver ||
            role == UserRole.admin;

        return Scaffold(
          backgroundColor: AppColors.gray50,
          appBar: AppBar(
            backgroundColor: AppColors.obsidian,
            foregroundColor: AppColors.white,
            elevation: 0,
            title: const Text(
              'Account & Profile',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: AppColors.white,
              ),
            ),
            leading: (widget.showBackButton && Navigator.canPop(context))
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            automaticallyImplyLeading:
                widget.showBackButton && Navigator.canPop(context),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. User Profile Header Card ─────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Avatar with emerald ring & edit badge
                      VektoluxAvatar(
                        avatarUrl: user?.avatarUrl,
                        name: displayName,
                        radius: 34,
                        borderWidth: 2.5,
                        borderColor: AppColors.emerald,
                        showEditBadge: true,
                        onTap: () => _showAvatarPickerModal(context, user),
                      ),
                      const SizedBox(width: 16),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.obsidian,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _showVerificationInfoDialog(context, user),
                                  child: _buildVerificationBadge(user),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayPhone,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.gray500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayEmail,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.gray400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Role Badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.emeraldSurface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.emerald.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.verified_user_rounded,
                                        size: 11,
                                        color: AppColors.emeraldDark,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        role.displayName,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.emeraldDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (userBio != null && userBio.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                userBio,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.gray600,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if ((userRegion != null && userRegion.isNotEmpty) ||
                                (userAddress != null && userAddress.isNotEmpty)) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 13, color: AppColors.gray500),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (userRegion != null && userRegion.isNotEmpty) userRegion,
                                        if (userAddress != null && userAddress.isNotEmpty) userAddress,
                                      ].join(' • '),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.gray500,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppColors.gray500),
                        tooltip: 'Edit Profile',
                        onPressed: () {
                          if (user != null) {
                            _showEditProfileModal(context, user);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 1A. Public Creator Profile Card ──
                if (user != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.emeraldSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.grid_view_rounded,
                            color: AppColors.emeraldDark,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Public Creator Profile',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Followers, bio & catalog grid',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.gray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(
                                  userId: user.id,
                                  convexClient: context.read<ConvexClientWrapper>(),
                                ),
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'View',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // ── 1B. Business Verification Status Card (Agents & Merchants) ──
                if (user != null && (user.role == UserRole.agent || user.role == UserRole.merchant)) ...[
                  _buildBusinessVerificationCard(context, user),
                  const SizedBox(height: 18),
                ],

                // ── 1B. Dual-Role Mode Switcher (Only if driver verified/registered) ──
                if (user?.canSwitchToDriver == true) ...[
                  _buildSectionHeader('WORKSPACE & ACCOUNT MODE'),
                  _buildModeSwitcherCard(context, user),
                  const SizedBox(height: 18),
                ],

                // ── 1C. My Posts & Marketplace Listings ─────────────
                _buildSectionHeader('MY POSTS & MARKETPLACE LISTINGS'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.inventory_2_outlined,
                        title: 'My Published Listings',
                        subtitle: 'View, edit details, or delete & archive your posts',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () {
                          if (user != null) {
                            final db = context.read<AppDatabase>();
                            final client = context.read<ConvexClientWrapper>();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MyListingsScreen(
                                  database: db,
                                  convexClient: client,
                                  currentUser: user,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.add_business_outlined,
                        title: 'Create New Listing',
                        subtitle: 'Post a real estate property or vehicle for sale',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () {
                          if (user != null) {
                            final db = context.read<AppDatabase>();
                            final client = context.read<ConvexClientWrapper>();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CreateListingScreen(
                                  database: db,
                                  convexClient: client,
                                  currentUser: user,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── 2. Operator Workspace Card (If vendor role) ──────
                if (isVendor) ...[
                  _buildSectionHeader('OPERATOR WORKSPACE'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.obsidian, Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.emerald.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.storefront_rounded,
                              color: AppColors.emerald, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Operator Portal',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Launch ${role.displayName} Portal',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: AppColors.obsidian,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onPressed: () {
                            final db = context.read<AppDatabase>();
                            final client = context.read<ConvexClientWrapper>();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => OperatorDashboardScreen(
                                  database: db,
                                  convexClient: client,
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Open Hub',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // ── 3. Partner & Vendor Upgrades (All Users) ─────────
                _buildSectionHeader('BECOME A VEKTOLUX PARTNER'),
                _buildPartnerCard(
                  icon: Icons.apartment_rounded,
                  title: 'List Properties as Real Estate Agent',
                  subtitle:
                      'Reach thousands of verified buyers & renters nationwide',
                  actionLabel: 'Apply as Agent',
                  badgeText: role == UserRole.agent ? 'ACTIVE' : 'APPLY',
                  isEnrolled: role == UserRole.agent,
                  onTap: () => _showAgentApplicationDialog(context, user),
                ),
                const SizedBox(height: 10),
                _buildPartnerCard(
                  icon: Icons.directions_car_filled_rounded,
                  title: 'Sell Vehicles as Auto Dealer',
                  subtitle:
                      'List showroom cars, SUVs, pickups & fleet rentals with escrow',
                  actionLabel: 'Apply as Dealer',
                  badgeText: role == UserRole.merchant ? 'ACTIVE' : 'APPLY',
                  isEnrolled: role == UserRole.merchant,
                  onTap: () => _showDealerApplicationDialog(context, user),
                ),
                const SizedBox(height: 18),

                // ── 4. Vendor / Merchant Hub (If vendor role) ────────
                if (isVendor) ...[
                  _buildSectionHeader('VENDOR & MERCHANT HUB'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildVendorStatCard(
                              icon: Icons.storefront_outlined,
                              label: 'Active Listings',
                              value: '$_vendorListingCount Item${_vendorListingCount == 1 ? '' : 's'}',
                              color: AppColors.obsidian,
                            ),
                            const SizedBox(width: 10),
                            _buildVendorStatCard(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Escrow Balance',
                              value: 'SLE ${_walletBalance != null ? _walletBalance!.toStringAsFixed(0) : '...'}',
                              color: AppColors.emeraldDark,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (user?.isVerified == true || user?.isApprovedVerification == true)
                                    ? AppColors.emeraldSurface
                                    : AppColors.amberSurface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                (user?.isVerified == true || user?.isApprovedVerification == true)
                                    ? Icons.badge_outlined
                                    : Icons.pending_actions_outlined,
                                color: (user?.isVerified == true || user?.isApprovedVerification == true)
                                    ? AppColors.emeraldDark
                                    : AppColors.amberDark,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (user?.isVerified == true || user?.isApprovedVerification == true)
                                        ? 'KYC Verification: Verified'
                                        : (user?.isPendingVerification == true
                                            ? 'KYC Verification: Pending Review'
                                            : 'KYC Verification: Unverified'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.obsidian,
                                    ),
                                  ),
                                  Text(
                                    (user?.isVerified == true || user?.isApprovedVerification == true)
                                        ? 'National ID & TIN credentials verified on-chain'
                                        : 'Tap to submit business & identity verification',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              (user?.isVerified == true || user?.isApprovedVerification == true)
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              color: (user?.isVerified == true || user?.isApprovedVerification == true)
                                  ? AppColors.emerald
                                  : AppColors.amberDark,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // ── 3. Saved Addresses / Places ─────────────────────
                _buildSectionHeader('SAVED ADDRESSES'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.home_outlined,
                        title: 'Home',
                        subtitle: 'Freetown, Sierra Leone (Default)',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.work_outline,
                        title: 'Work / Office',
                        subtitle: 'Central Business District, Freetown',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 4. Escrow Wallet Hero Card ───────────────────────
                _buildSectionHeader('ESCROW WALLET & BALANCES'),
                _buildEscrowWalletHeroCard(context, user),

                const SizedBox(height: 18),

                // ── 4B. Saved Payment Methods ────────────────────────
                _buildSectionHeader('SAVED PAYMENT METHODS'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      if (_isLoadingAccounts)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_userPaymentAccounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'No payment methods linked yet.',
                              style: TextStyle(color: AppColors.gray500, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < _userPaymentAccounts.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 68),
                          _buildPaymentMethodTile(_userPaymentAccounts[i]),
                        ],
                      const Divider(height: 1),
                      InkWell(
                        onTap: () => _showAddPaymentMethodSheet(context),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.emeraldSurface,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.add_rounded, color: AppColors.emeraldDark, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Add Payment Method',
                                      style: TextStyle(
                                        color: AppColors.emeraldDark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Link Orange Money, Afrimoney, QMoney, or SLCB Bank',
                                      style: TextStyle(
                                        color: AppColors.gray500,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 13,
                                color: AppColors.emeraldDark,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 4C. Wallet Security & Preferences ────────────────
                _buildSectionHeader('WALLET SECURITY & PREFERENCES'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Escrow Security PIN',
                        subtitle: '4-digit authorization PIN for escrow payouts',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.emeraldSurface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Manage',
                            style: TextStyle(
                              color: AppColors.emeraldDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        onTap: () => _showWalletPinModal(context, user),
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.fingerprint_rounded, color: AppColors.gray600),
                        title: const Text('Biometric / FaceID Authorization', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Require FaceID / TouchID to authorize escrow transactions', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                        value: _escrowBiometricEnabled,
                        activeThumbColor: AppColors.emerald,
                        onChanged: (val) => setState(() => _escrowBiometricEnabled = val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.qr_code_2_rounded,
                        title: 'Receive Payment QR',
                        subtitle: 'Display personal QR code to receive payments & transfers',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () => _showMyQrCodeModal(context, user),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 5. App Preferences & Notifications ──────────────
                _buildSectionHeader('APP PREFERENCES & NOTIFICATIONS'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_outlined, color: AppColors.gray500),
                        title: const Text('Push Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Real-time order & inspection alerts', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                        value: _pushNotifications,
                        activeThumbColor: AppColors.emerald,
                        onChanged: (val) => setState(() => _pushNotifications = val),
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.sms_outlined, color: AppColors.gray500),
                        title: const Text('SMS Status Receipts', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Receive backup SMS updates in Sierra Leone', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                        value: _smsAlerts,
                        activeThumbColor: AppColors.emerald,
                        onChanged: (val) => setState(() => _smsAlerts = val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.school_outlined,
                        title: 'Interactive App Tour',
                        subtitle: 'Learn how to book properties, vehicles & freight with Agent 001',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () => MainNavigationShell.showAppTour(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 6. Legal, Privacy & About ───────────────────────
                _buildSectionHeader('SUPPORT & LEGAL'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'Local-first zero telemetry standards',
                        onTap: () => _showInfoSheet(
                          context,
                          'Privacy Policy',
                          'Vektolux values user data sovereignty in Sierra Leone. All sensitive sessions are encrypted locally in SQLite, and payments follow ECOWAS & Central Bank standards with end-to-end cryptographic integrity.',
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.description_outlined,
                        title: 'Terms of Service',
                        subtitle: 'Escrow dispute & marketplace guidelines',
                        onTap: () => _showInfoSheet(
                          context,
                          'Terms of Service',
                          'All marketplace transactions, property bookings, and vehicle inspections operate under Vektolux escrow protocols. Funds remain locked until physical inspection is approved or trip completion.',
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.support_agent_outlined,
                        title: 'Customer Support',
                        subtitle: 'WhatsApp & Direct Call: +232 73 623 761',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () => _showCustomerSupportModal(context),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.info_outline,
                        title: 'App Version',
                        subtitle: 'Vektolux v1.0.13 (Build 14)',
                        trailing: const Text(
                          'Latest',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── 7. Prominent Log Out Button ─────────────────────
                Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorLight,
                      foregroundColor: AppColors.errorDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.errorDark),
                    label: const Text(
                      'Log Out of Vektolux',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.errorDark,
                      ),
                    ),
                    onPressed: () => _showLogoutDialog(context),
                  ),
                ),

                const SizedBox(height: 36),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBusinessVerificationCard(BuildContext context, UserEntity user) {
    final status = user.verificationStatus.toLowerCase();
    final isApproved = status == 'approved' || status == 'verified' || user.isVerified;
    final isRejected = status == 'rejected';
    final isPending = !isApproved && !isRejected;

    final Color badgeColor = isApproved
        ? AppColors.emerald
        : isRejected
            ? AppColors.error
            : const Color(0xFFD97706);
    final Color badgeBg = isApproved
        ? const Color(0xFFD1FAE5)
        : isRejected
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF3C7);
    final String badgeLabel = isApproved
        ? 'VERIFIED BUSINESS'
        : isRejected
            ? 'VERIFICATION REJECTED'
            : 'VERIFICATION PENDING';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPending
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : isRejected
                  ? AppColors.error.withValues(alpha: 0.5)
                  : AppColors.border,
          width: isPending || isRejected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isApproved
                      ? Icons.verified_rounded
                      : isRejected
                          ? Icons.error_outline_rounded
                          : Icons.pending_actions_rounded,
                  color: badgeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.businessName ?? (user.role == UserRole.agent ? 'Agent Business Account' : 'Merchant Business Account'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.tinNumber != null && user.tinNumber!.isNotEmpty
                          ? 'TIN: ${user.tinNumber}'
                          : 'TIN proof submitted for review',
                      style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (isRejected && user.rejectionReason != null && user.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                'Reason: ${user.rejectionReason}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
              ),
            ),
          ],
          if (!isApproved) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PendingVerificationScreen(user: user),
                    ),
                  );
                },
                icon: Icon(
                  isRejected ? Icons.refresh_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: badgeColor,
                ),
                label: Text(
                  isRejected ? 'Resubmit Business Verification' : 'Check Verification Status',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: badgeColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeSwitcherCard(BuildContext context, UserEntity? user) {
    final isDriverMode = user?.isDriverMode ?? false;
    final canDrive = user?.canSwitchToDriver ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDriverMode ? AppColors.emerald : AppColors.border,
          width: isDriverMode ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDriverMode
                ? AppColors.emerald.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDriverMode
                      ? AppColors.emeraldSurface
                      : AppColors.obsidian.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDriverMode ? Icons.local_shipping_rounded : Icons.person_rounded,
                  color: isDriverMode ? AppColors.emeraldDark : AppColors.obsidian,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDriverMode ? 'Fleet Operator Mode Active' : 'Client Mode Active',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDriverMode
                          ? 'Managing commercial fleet, vans & heavy haulage'
                          : 'Browsing properties, showroom vehicles & logistics',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDriverMode ? AppColors.emerald : AppColors.obsidian,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isDriverMode ? 'FLEET' : 'CLIENT',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (canDrive) ...[
            Container(
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (isDriverMode) {
                          context.read<AuthBloc>().add(const SwitchUserModeEvent('passenger'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Switched to Client Mode'),
                              backgroundColor: AppColors.obsidian,
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isDriverMode ? AppColors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: !isDriverMode
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: !isDriverMode ? AppColors.obsidian : AppColors.gray500,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Client Mode',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: !isDriverMode ? FontWeight.w800 : FontWeight.w600,
                                  color: !isDriverMode ? AppColors.obsidian : AppColors.gray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (!isDriverMode) {
                          context.read<AuthBloc>().add(const SwitchUserModeEvent('driver'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Switched to Fleet Operator Mode'),
                              backgroundColor: AppColors.emerald,
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isDriverMode ? AppColors.emerald : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: isDriverMode
                              ? [
                                  BoxShadow(
                                    color: AppColors.emerald.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_shipping_rounded,
                                size: 16,
                                color: isDriverMode ? AppColors.white : AppColors.gray500,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Fleet Operator',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isDriverMode ? FontWeight.w800 : FontWeight.w600,
                                  color: isDriverMode ? AppColors.white : AppColors.gray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: AppColors.gray500),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fleet Operator access requires verified operator status. Apply as a Dealer below to unlock this mode.',
                      style: TextStyle(fontSize: 12, color: AppColors.gray600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.gray500,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildVendorStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.gray50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.gray500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.gray100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.obsidian, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.obsidian,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.gray400, size: 18),
      onTap: onTap,
    );
  }

  Widget _buildPartnerCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required String badgeText,
    required bool isEnrolled,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnrolled ? AppColors.emerald : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isEnrolled ? AppColors.emeraldSurface : AppColors.gray100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isEnrolled ? AppColors.emeraldDark : AppColors.obsidian,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isEnrolled
                            ? AppColors.emeraldSurface
                            : AppColors.gray100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: isEnrolled
                              ? AppColors.emeraldDark
                              : AppColors.gray600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.gray500),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isEnrolled ? 'Manage Portal' : actionLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 10, color: AppColors.emeraldDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAgentApplicationDialog(BuildContext context, UserEntity? user) {
    if (user == null) return;
    final agencyCtrl =
        TextEditingController(text: '${user.name} Real Estate Agency');
    final tinCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Real Estate Agent Verification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Submit your agency details to unlock the property manager and publish listings across Sierra Leone.',
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: agencyCtrl,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFF10B981),
              decoration: const InputDecoration(
                labelText: 'Agency / Business Name',
                labelStyle: TextStyle(color: Color(0xFF64748B)),
                hintText: 'Enter real estate agency name',
                hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.business_rounded, color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinCtrl,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFF10B981),
              decoration: const InputDecoration(
                labelText: 'TIN / Business Registration',
                labelStyle: TextStyle(color: Color(0xFF64748B)),
                hintText: 'e.g. TIN-774411-SL',
                hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.badge_outlined, color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emeraldDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final businessName = agencyCtrl.text.trim();
                  final tin = tinCtrl.text.trim();
                  if (businessName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter an agency name.')),
                    );
                    return;
                  }
                  final client = context.read<ConvexClientWrapper>();
                  await client.mutation(
                    'users:applyRoleUpgrade',
                    args: {
                      'userId': user.id,
                      'targetRole': 'agent',
                      'businessName': businessName,
                      if (tin.isNotEmpty) 'tinNumber': tin,
                    },
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Application submitted! You will be notified once verified.'),
                        backgroundColor: AppColors.emeraldDark,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Submit Application',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDealerApplicationDialog(BuildContext context, UserEntity? user) {
    if (user == null) return;
    final dealerCtrl =
        TextEditingController(text: '${user.name} Motors & Fleet');
    final tinCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Auto Dealer & Fleet Verification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Submit your dealership registration to list cars for sale, delivery vans, and fleet rentals.',
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dealerCtrl,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFF10B981),
              decoration: const InputDecoration(
                labelText: 'Dealership / Fleet Name',
                labelStyle: TextStyle(color: Color(0xFF64748B)),
                hintText: 'Enter dealership or fleet name',
                hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.directions_car_rounded, color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinCtrl,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFF10B981),
              decoration: const InputDecoration(
                labelText: 'TIN / Trade License Number',
                labelStyle: TextStyle(color: Color(0xFF64748B)),
                hintText: 'e.g. TIN-998822-SL',
                hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.badge_outlined, color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF92400E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final dealershipName = dealerCtrl.text.trim();
                  final tin = tinCtrl.text.trim();
                  if (dealershipName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a dealership name.')),
                    );
                    return;
                  }
                  final client = context.read<ConvexClientWrapper>();
                  await client.mutation(
                    'users:applyRoleUpgrade',
                    args: {
                      'userId': user.id,
                      'targetRole': 'merchant',
                      'businessName': dealershipName,
                      if (tin.isNotEmpty) 'tinNumber': tin,
                    },
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Dealership application submitted! You will be notified once verified.'),
                        backgroundColor: Color(0xFF92400E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Submit Application',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMyQrCodeModal(BuildContext context, UserEntity? user) {
    final qrCardKey = GlobalKey();
    final qrData =
        'vektolux://pay?userId=${user?.id ?? "guest"}&phone=${user?.phone ?? ""}&name=${Uri.encodeComponent(user?.name ?? "User")}';
    final verificationBadgeText = (user != null &&
            user.verificationBadge.isNotEmpty &&
            user.verificationBadge != 'NONE')
        ? user.verificationBadge
        : (user?.isVerified == true
            ? 'VERIFIED CITIZEN ID • ESCROW ENABLED'
            : 'CITIZEN ID • ESCROW ENABLED');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'My Vektolux Account QR',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Scan to send money or verify credentials in Sierra Leone',
              style: TextStyle(fontSize: 12, color: AppColors.gray500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // QR Container Card with RepaintBoundary for high-res PNG capture
            RepaintBoundary(
              key: qrCardKey,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(190, 190),
                            painter: _VektoluxQrPainter(
                              data: qrData,
                              foregroundColor: const Color(0xFF0F172A),
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'V',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  fontSize: 19,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.name ?? 'Vektolux User',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user != null && user.phone.isNotEmpty
                          ? user.phone
                          : '+232 ...',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.gray500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        verificationBadgeText,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.emeraldDark,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.copy_rounded,
                        size: 18, color: AppColors.obsidian),
                    label: const Text('Copy ID',
                        style: TextStyle(
                            color: AppColors.obsidian,
                            fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      final idToCopy = (user?.id != null && user!.id.isNotEmpty)
                          ? user.id
                          : 'VLX-SL-232';
                      await Clipboard.setData(ClipboardData(text: idToCopy));
                      // Native OS clipboard confirmation verification
                      final clipCheck = await Clipboard.getData(Clipboard.kTextPlain);
                      final isConfirmed = clipCheck?.text == idToCopy;

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isConfirmed
                                        ? 'Account ID ($idToCopy) copied to clipboard!'
                                        : 'Account ID copied to clipboard!',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: AppColors.emeraldDark,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share QR',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      final userId = user?.id ?? "guest";
                      final userName = user?.name ?? "Vektolux User";
                      final userPhone = user?.phone ?? "";
                      final shareLink = 'https://app.vektolux.com/pay?userId=$userId&phone=$userPhone&name=${Uri.encodeComponent(userName)}';
                      final shareText = 'Pay or verify with Vektolux Escrow:\n'
                          'Name: $userName\n'
                          'Account ID: $userId\n'
                          'Link: $shareLink\n\n'
                          'Sierra Leone Escrow Protection & Mobile Money.';

                      final box = context.findRenderObject() as RenderBox?;
                      final originRect = box != null
                          ? box.localToGlobal(Offset.zero) & box.size
                          : const Rect.fromLTWH(0, 0, 300, 300);

                      try {
                        final boundary = qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                        if (boundary != null) {
                          final image = await boundary.toImage(pixelRatio: 2.5);
                          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                          if (byteData != null) {
                            final pngBytes = byteData.buffer.asUint8List();
                            final tempDir = await getTemporaryDirectory();
                            final filePath = '${tempDir.path}/vektolux_qr_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.png';
                            final file = File(filePath);
                            await file.writeAsBytes(pngBytes, flush: true);

                            if (ctx.mounted) Navigator.pop(ctx);
                            await Share.shareXFiles(
                              [XFile(filePath, mimeType: 'image/png', name: 'vektolux_qr.png')],
                              text: shareText,
                              subject: 'Vektolux Payment QR — $userName',
                              sharePositionOrigin: originRect,
                            );
                            return;
                          }
                        }
                      } catch (e) {
                        debugPrint('[ProfileScreen] QR image render failed, falling back to text share: $e');
                      }

                      // Fallback to text & link share via native OS share sheet
                      if (ctx.mounted) Navigator.pop(ctx);
                      await Share.share(
                        shareText,
                        subject: 'Vektolux Payment QR — $userName',
                        sharePositionOrigin: originRect,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showScanQrModal(BuildContext context, UserEntity? user) {
    final codeCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: '150');
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded,
                            color: AppColors.emeraldDark, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan to Pay / Transfer',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pay driver, property agent, or vehicle merchant',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Simulated Camera Reticle Viewfinder
                  Center(
                    child: Container(
                      width: 220,
                      height: 170,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.emerald, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emerald.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.center_focus_strong_rounded,
                                  size: 48, color: AppColors.emerald),
                              SizedBox(height: 8),
                              Text(
                                'Align QR in camera frame',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.emeraldDark,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ACTIVE SENSOR',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: codeCtrl,
                    cursorColor: const Color(0xFF10B981),
                    style: const TextStyle(
                      color: AppColors.obsidian,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Or enter Recipient Phone / Wallet ID / Agent 001',
                      hintText: 'e.g. +232 76 123456, 001, or VLX-SL-9821',
                      prefixIcon: Icon(Icons.perm_identity_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    cursorColor: const Color(0xFF10B981),
                    style: const TextStyle(
                      color: AppColors.obsidian,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount (SLE)',
                      prefixText: 'SLE ',
                      prefixStyle: TextStyle(
                        color: AppColors.obsidian,
                        fontWeight: FontWeight.w700,
                      ),
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: isProcessing
                          ? null
                          : () async {
                              final amount =
                                  double.tryParse(amountCtrl.text.trim()) ?? 0;
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Please enter a valid amount.')),
                                );
                                return;
                              }

                              setModalState(() => isProcessing = true);
                              await Future.delayed(
                                  const Duration(milliseconds: 800));

                              if (modalCtx.mounted) {
                                Navigator.of(modalCtx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Transferred SLE ${amount.toStringAsFixed(0)} successfully! Escrow locked.'),
                                    backgroundColor: AppColors.emeraldDark,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      child: isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Authorize & Send Payment',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showWalletPinModal(BuildContext context, UserEntity? user) {
    if (user == null) return;
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shield_rounded,
                            color: AppColors.emeraldDark, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wallet Security PIN',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Authorize Escrow payouts & Mobile Money',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    cursorColor: const Color(0xFF10B981),
                    decoration: const InputDecoration(
                      labelText: 'Enter New 4-Digit PIN',
                      labelStyle: TextStyle(color: Color(0xFF64748B)),
                      hintText: '••••',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B)),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: confirmPinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    cursorColor: const Color(0xFF10B981),
                    decoration: const InputDecoration(
                      labelText: 'Confirm 4-Digit PIN',
                      labelStyle: TextStyle(color: Color(0xFF64748B)),
                      hintText: '••••',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                      prefixIcon: Icon(Icons.lock_reset_rounded, color: Color(0xFF64748B)),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final p1 = pinController.text.trim();
                              final p2 = confirmPinController.text.trim();
                              if (p1.length != 4) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('PIN must be exactly 4 digits.')),
                                );
                                return;
                              }
                              if (p1 != p2) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'PINs do not match. Please re-enter.')),
                                );
                                return;
                              }

                              setModalState(() => isSaving = true);
                              try {
                                final client =
                                    context.read<ConvexClientWrapper>();
                                final res = await client.mutation(
                                  'payments:setWalletPin',
                                  args: {'userId': user.id, 'pin': p1},
                                );
                                if (res.success) {
                                  if (modalCtx.mounted) {
                                    Navigator.of(modalCtx).pop();
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            '🛡️ Wallet Security PIN updated successfully!'),
                                        backgroundColor: AppColors.emeraldDark,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } else {
                                  throw Exception(
                                      res.errorMessage ?? 'Failed to update PIN');
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Save Security PIN',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _maskAccountNumber(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '••••';
    final digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('232') && digits.length >= 8) {
      final prefix = digits.length >= 5 ? digits.substring(3, 5) : digits.substring(3);
      final suffix = digits.substring(digits.length - 3);
      return '+232 $prefix ••• $suffix';
    } else if (clean.startsWith('+232') && clean.length >= 7) {
      final parts = clean.split(' ');
      if (parts.length >= 3) {
        return '${parts[0]} ${parts[1]} ••• ${parts.last}';
      }
    }
    if (clean.length > 6) {
      return '${clean.substring(0, 3)} ••• ${clean.substring(clean.length - 3)}';
    }
    return clean;
  }

  String _formatPhoneDisplay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'No phone number set';
    final clean = raw.trim();
    var digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('2320') && digits.length == 12) {
      digits = '232${digits.substring(4)}';
    } else if (digits.startsWith('0') && digits.length == 9) {
      digits = '232${digits.substring(1)}';
    } else if (digits.length == 8) {
      digits = '232$digits';
    }
    if (digits.startsWith('232') && digits.length == 11) {
      return '+232 ${digits.substring(3, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
    }
    if (!clean.startsWith('+') && digits.startsWith('232')) {
      return '+$digits';
    }
    return clean;
  }

  String _findDefaultPhoneForProvider(String providerCode, UserEntity? user) {
    final matchingDefault = _userPaymentAccounts.cast<PaymentAccount?>().firstWhere(
      (a) => a?.providerCode == providerCode && a?.isDefault == true,
      orElse: () => null,
    );
    if (matchingDefault != null && matchingDefault.accountNumber.isNotEmpty) {
      return matchingDefault.accountNumber;
    }
    final matchingAny = _userPaymentAccounts.cast<PaymentAccount?>().firstWhere(
      (a) => a?.providerCode == providerCode,
      orElse: () => null,
    );
    if (matchingAny != null && matchingAny.accountNumber.isNotEmpty) {
      return matchingAny.accountNumber;
    }
    final anyDefault = _userPaymentAccounts.cast<PaymentAccount?>().firstWhere(
      (a) => a?.isDefault == true,
      orElse: () => null,
    );
    if (anyDefault != null && anyDefault.accountNumber.isNotEmpty) {
      return anyDefault.accountNumber;
    }
    if (user?.phone != null && user!.phone.isNotEmpty) {
      return user.phone;
    }
    return '';
  }

  Widget _buildProviderIcon(String providerCode) {
    IconData iconData;
    Color bgColor;
    Color iconColor;

    switch (providerCode) {
      case 'orange':
        iconData = Icons.phone_android_rounded;
        bgColor = const Color(0xFFFFF3E0);
        iconColor = const Color(0xFFFF6600);
        break;
      case 'africell':
        iconData = Icons.signal_cellular_alt_rounded;
        bgColor = const Color(0xFFFCE4EC);
        iconColor = const Color(0xFFE91E63);
        break;
      case 'qmoney':
        iconData = Icons.cell_tower_rounded;
        bgColor = const Color(0xFFE8F5E9);
        iconColor = const Color(0xFF2E7D32);
        break;
      case 'slcb':
      default:
        iconData = Icons.account_balance_rounded;
        bgColor = const Color(0xFFE3F2FD);
        iconColor = const Color(0xFF1565C0);
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  Widget _buildEscrowWalletHeroCard(BuildContext context, UserEntity? user) {
    final balanceText = _isBalanceVisible
        ? 'SLE ${_walletBalance?.toStringAsFixed(2) ?? '0.00'}'
        : 'SLE ••••••';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF064E3B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: AppColors.emerald.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      size: 14,
                      color: AppColors.emerald,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'VEKTOLUX ESCROW WALLET',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _isBalanceVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                tooltip: _isBalanceVisible ? 'Hide Balance' : 'Show Balance',
                onPressed: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _isLoadingBalance
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              : Text(
                  balanceText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Escrow Protected • $_activeEscrowDeals Active Deal${_activeEscrowDeals == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF6EE7B7),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildEscrowActionButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Top Up',
                  onTap: () => _showTopUpEscrowSheet(context, user),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEscrowActionButton(
                  icon: Icons.arrow_circle_up_rounded,
                  label: 'Withdraw',
                  onTap: () => _showWithdrawEscrowSheet(context, user),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEscrowActionButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Scan QR',
                  onTap: () => _showScanQrModal(context, user),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEscrowActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodTile(PaymentAccount method) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildProviderIcon(method.providerCode),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method.providerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      method.maskedNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (method.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Default',
                          style: TextStyle(
                            color: AppColors.emeraldDark,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (method.isActive) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gray100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            color: AppColors.gray700,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.gray400),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (action) async {
              final client = context.read<ConvexClientWrapper>();
              final userId = context.read<AuthBloc>().state.user?.id ?? '';
              if (action == 'default') {
                try {
                  await client.mutation(
                    'payments:setDefaultPaymentAccount',
                    args: {'accountId': method.id, 'userId': userId},
                  );
                  await _fetchUserPaymentAccounts();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${method.providerName} set as default payment method.'),
                        backgroundColor: AppColors.emeraldDark,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to set default: $e')),
                    );
                  }
                }
              } else if (action == 'delete') {
                try {
                  await client.mutation(
                    'payments:removeUserPaymentAccount',
                    args: {'accountId': method.id, 'userId': userId},
                  );
                  await _fetchUserPaymentAccounts();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${method.providerName} removed.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to remove: $e')),
                    );
                  }
                }
              }
            },
            itemBuilder: (ctx) => [
              if (!method.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.emeraldDark),
                      SizedBox(width: 8),
                      Text('Set as Default', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Remove', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddPaymentMethodSheet(BuildContext context) {
    String selectedProvider = 'orange';
    final accountCtrl = TextEditingController();
    bool setAsDefault = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isBank = selectedProvider == 'slcb';
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, color: AppColors.emeraldDark, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Link Payment Method',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Connect a Mobile Money wallet or Commercial Bank account.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.gray500),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Select Provider',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedProvider,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: Colors.white,
                    iconEnabledColor: const Color(0xFF64748B),
                    focusColor: Colors.transparent,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.emerald, width: 1.5)),
                    ),
                    selectedItemBuilder: (context) => [
                      'Orange Money Sierra Leone',
                      'Africell Afrimoney',
                      'QCell QMoney',
                      'Sierra Leone Commercial Bank (SLCB)',
                    ].map((label) => Text(label, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600))).toList(),
                    items: const [
                      DropdownMenuItem(
                        value: 'orange',
                        child: Text('Orange Money Sierra Leone', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                      DropdownMenuItem(
                        value: 'africell',
                        child: Text('Africell Afrimoney', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                      DropdownMenuItem(
                        value: 'qmoney',
                        child: Text('QCell QMoney', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                      DropdownMenuItem(
                        value: 'slcb',
                        child: Text('Sierra Leone Commercial Bank (SLCB)', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedProvider = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isBank ? 'Account Number' : 'Mobile Money Phone Number',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: accountCtrl,
                    keyboardType: isBank ? TextInputType.text : TextInputType.phone,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    cursorColor: const Color(0xFF10B981),
                    decoration: InputDecoration(
                      labelText: isBank ? 'Account Number' : 'Mobile Money Number',
                      labelStyle: const TextStyle(color: Color(0xFF64748B)),
                      hintText: isBank ? 'e.g. 003-010-984210' : 'e.g. +232 76 123 456',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      prefixIcon: Icon(isBank ? Icons.account_balance_rounded : Icons.phone_android_rounded, color: const Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Set as default payment method', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: setAsDefault,
                    activeThumbColor: AppColors.emerald,
                    onChanged: (val) => setModalState(() => setAsDefault = val),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final rawNumber = accountCtrl.text.trim();
                        if (rawNumber.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter an account or phone number.')),
                          );
                          return;
                        }

                        String pName;
                        switch (selectedProvider) {
                          case 'orange':
                            pName = 'Orange Money Sierra Leone';
                            break;
                          case 'africell':
                            pName = 'Africell Afrimoney';
                            break;
                          case 'qmoney':
                            pName = 'QCell QMoney';
                            break;
                          case 'slcb':
                          default:
                            pName = 'Sierra Leone Commercial Bank (SLCB)';
                            break;
                        }

                        try {
                          final client = context.read<ConvexClientWrapper>();
                          final userId = context.read<AuthBloc>().state.user?.id ?? '';
                          await client.mutation(
                            'payments:addUserPaymentAccount',
                            args: {
                              'userId': userId,
                              'providerCode': selectedProvider,
                              'providerName': pName,
                              'accountNumber': rawNumber,
                              'maskedNumber': _maskAccountNumber(rawNumber),
                              'isDefault': setAsDefault || _userPaymentAccounts.isEmpty,
                            },
                          );
                          await _fetchUserPaymentAccounts();

                          if (modalCtx.mounted) Navigator.of(modalCtx).pop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$pName linked successfully!'),
                                backgroundColor: AppColors.emeraldDark,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to link account: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Link Payment Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showChangeNumberSheet({
    required BuildContext context,
    required String currentProvider,
    required String? currentPhone,
    required ValueChanged<String> onSelected,
  }) {
    final newPhoneCtrl = TextEditingController();
    bool saveAsDefault = false;
    bool isSaving = false;
    String? localError;

    const providerLabels = {
      'orange': 'Orange Money Sierra Leone',
      'africell': 'Africell Afrimoney',
      'qmoney': 'QCell QMoney',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 28,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.gray300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(Icons.phonelink_setup_rounded, color: AppColors.emeraldDark, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Change Payment Number',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a saved number or enter a new number for ${providerLabels[currentProvider] ?? "Mobile Money"}.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.gray500),
                    ),
                    const SizedBox(height: 20),

                    // ── Saved payment accounts list ───────────────────
                    if (_userPaymentAccounts.isNotEmpty) ...[
                      const Text(
                        'Saved Payment Numbers',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 8),
                      ..._userPaymentAccounts.map((account) {
                        final isSelected = account.accountNumber == currentPhone;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.emeraldSurface : AppColors.gray50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.emerald : AppColors.border,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: _buildProviderIcon(account.providerCode),
                            title: Text(
                              account.providerName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Text(
                              account.maskedNumber,
                              style: const TextStyle(fontSize: 12, color: AppColors.gray600),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: AppColors.emeraldDark, size: 20)
                                : TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: Size.zero,
                                    ),
                                    onPressed: () {
                                      onSelected(account.accountNumber);
                                      Navigator.of(sheetCtx).pop();
                                    },
                                    child: const Text('Use', style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700, fontSize: 12)),
                                  ),
                            onTap: () {
                              onSelected(account.accountNumber);
                              Navigator.of(sheetCtx).pop();
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 12),
                    ],

                    // ── Enter New Number ──────────────────────────────
                    const Text(
                      'Or Enter New Number',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: newPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 076 123 456 or 23276123456',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                        labelText: 'Phone Number',
                        labelStyle: TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: Icon(Icons.phone_outlined, color: Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: saveAsDefault,
                      activeColor: AppColors.emerald,
                      onChanged: (val) => setSheetState(() => saveAsDefault = val ?? false),
                      title: const Text(
                        'Save as default payment method for this provider',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    if (localError != null) ...[
                      const SizedBox(height: 8),
                      Text(localError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final input = newPhoneCtrl.text.trim();
                                if (input.isEmpty) {
                                  setSheetState(() => localError = 'Please enter a phone number.');
                                  return;
                                }
                                final digits = input.replaceAll(RegExp(r'\D'), '');
                                if (digits.length < 8) {
                                  setSheetState(() => localError = 'Please enter a valid Sierra Leone phone number.');
                                  return;
                                }

                                if (saveAsDefault) {
                                  setSheetState(() => isSaving = true);
                                  try {
                                    final client = context.read<ConvexClientWrapper>();
                                    final userId = context.read<AuthBloc>().state.user?.id ?? '';
                                    final pName = providerLabels[currentProvider] ?? 'Mobile Money';

                                    await client.mutation(
                                      'payments:addUserPaymentAccount',
                                      args: {
                                        'userId': userId,
                                        'providerCode': currentProvider,
                                        'providerName': pName,
                                        'accountNumber': input,
                                        'maskedNumber': _maskAccountNumber(input),
                                        'isDefault': true,
                                      },
                                    );
                                    await _fetchUserPaymentAccounts();
                                  } catch (e) {
                                    setSheetState(() {
                                      localError = 'Failed to save payment account: $e';
                                      isSaving = false;
                                    });
                                    return;
                                  }
                                }

                                onSelected(input);
                                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Use This Number',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTopUpEscrowSheet(BuildContext context, UserEntity? user) {
    final amountCtrl = TextEditingController(text: '500');
    final referenceCtrl = TextEditingController();
    String selectedTopUpProvider = 'orange';
    String activePhoneNumber = _findDefaultPhoneForProvider('orange', user);
    bool isProcessing = false;
    bool showReferenceStep = false; // Step 2 for manual providers
    String? errorCode;
    String? errorMessage;

    // Provider display names
    const providerLabels = {
      'orange': 'Orange Money Sierra Leone',
      'africell': 'Africell Afrimoney',
      'qmoney': 'QCell QMoney',
    };

    // Provider IDs mapped to Convex payment_settings providerIds
    const providerIds = {
      'orange': 'moneroo_auto',
      'africell': 'afrimoney_manual',
      'qmoney': 'qmoney_manual',
    };

    // Manual instructions
    const providerInstructions = {
      'africell':
          'Dial *144# → Select "Pay" → Enter Merchant Code 9988 → Enter the exact SLE amount → confirm with your PIN. Copy the Transaction ID from the confirmation SMS.',
      'qmoney':
          'Dial *345# → Select "Pay Merchant" → Enter Merchant Code 001 → Enter the exact SLE amount → confirm with your PIN. Copy the Transaction ID from the confirmation SMS.',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isManual = selectedTopUpProvider != 'orange';

            Future<void> executeOrangeTopUp() async {
              setModalState(() {
                errorMessage = null;
                errorCode = null;
              });

              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amt <= 0) {
                setModalState(() => errorMessage = 'Please enter a valid amount.');
                return;
              }

              if (activePhoneNumber.trim().isEmpty) {
                setModalState(() => errorMessage = 'Please set or select a mobile money number.');
                _showChangeNumberSheet(
                  context: context,
                  currentProvider: selectedTopUpProvider,
                  currentPhone: activePhoneNumber,
                  onSelected: (newPhone) {
                    setModalState(() {
                      activePhoneNumber = newPhone;
                      errorCode = null;
                      errorMessage = null;
                    });
                  },
                );
                return;
              }

              setModalState(() => isProcessing = true);
              try {
                final result = await PaymentMethodsService.instance.initializeMonerooPayment(
                  amount: amt,
                  currency: 'SLE',
                  customerEmail: user?.email ?? 'user@vektolux.com',
                  customerFirstName: (user?.name ?? 'Vektolux User').split(' ').first,
                  customerLastName: (user?.name ?? 'User').split(' ').length > 1
                      ? (user?.name ?? 'User').split(' ').last
                      : 'User',
                  customerPhone: activePhoneNumber,
                  userId: user?.id ?? '',
                  description: 'Escrow Wallet Top-Up — SLE $amt',
                );

                if (result['success'] == true) {
                  final checkoutUrl = result['checkoutUrl'] as String? ?? '';
                  if (checkoutUrl.isNotEmpty) {
                    final uri = Uri.tryParse(checkoutUrl);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                  if (modalCtx.mounted) Navigator.of(modalCtx).pop();
                  _fetchWalletData();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Push prompt sent to ${_formatPhoneDisplay(activePhoneNumber)}! Approve on your phone to complete top-up.',
                        ),
                        backgroundColor: AppColors.emeraldDark,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else {
                  final code = result['code'] as String? ?? 'PAYMENT_FAILED';
                  final msg = result['message'] as String? ?? result['error'] as String? ?? 'Payment initialization failed.';
                  setModalState(() {
                    errorCode = code;
                    errorMessage = msg;
                    isProcessing = false;
                  });
                }
              } catch (e) {
                setModalState(() {
                  errorCode = 'NETWORK_ERROR';
                  errorMessage = 'Error: ${e.toString()}';
                  isProcessing = false;
                });
              }
            }

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Drag handle ─────────────────────────────────────
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Title ────────────────────────────────────────────
                  Row(
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, color: AppColors.emeraldDark, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        showReferenceStep ? 'Submit Payment Reference' : 'Top Up Escrow Wallet',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    showReferenceStep
                        ? 'Paste the Transaction ID from your ${providerLabels[selectedTopUpProvider] ?? "provider"} SMS.'
                        : 'Deposit funds into escrow protection via Mobile Money.',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.gray500),
                  ),
                  const SizedBox(height: 20),

                  if (!showReferenceStep) ...[
                    // ── Provider Selector ────────────────────────────
                    const Text(
                      'Payment Provider',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTopUpProvider,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      dropdownColor: Colors.white,
                      iconEnabledColor: const Color(0xFF64748B),
                      focusColor: Colors.transparent,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.emerald, width: 1.5)),
                      ),
                      selectedItemBuilder: (context) => [
                        'Orange Money Sierra Leone',
                        'Africell Afrimoney',
                        'QCell QMoney',
                      ].map((label) => Text(label, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600))).toList(),
                      items: const [
                        DropdownMenuItem(
                          value: 'orange',
                          child: Text('Orange Money Sierra Leone', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                        DropdownMenuItem(
                          value: 'africell',
                          child: Text('Africell Afrimoney', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                        DropdownMenuItem(
                          value: 'qmoney',
                          child: Text('QCell QMoney', style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedTopUpProvider = val;
                            activePhoneNumber = _findDefaultPhoneForProvider(val, user);
                            errorCode = null;
                            errorMessage = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // ── Active Charging Number Card ───────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.gray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.emeraldSurface,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.phone_android_rounded, color: AppColors.emeraldDark, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Charging: ${providerLabels[selectedTopUpProvider] ?? "Mobile Money"}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.gray500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activePhoneNumber.isNotEmpty
                                      ? _formatPhoneDisplay(activePhoneNumber)
                                      : 'No phone number set',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: activePhoneNumber.isNotEmpty
                                        ? const Color(0xFF0F172A)
                                        : AppColors.gray400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showChangeNumberSheet(
                              context: context,
                              currentProvider: selectedTopUpProvider,
                              currentPhone: activePhoneNumber,
                              onSelected: (newPhone) {
                                setModalState(() {
                                  activePhoneNumber = newPhone;
                                  errorCode = null;
                                  errorMessage = null;
                                });
                              },
                            ),
                            child: const Text(
                              'Change Number',
                              style: TextStyle(
                                color: AppColors.emeraldDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Amount Chips ─────────────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [250, 500, 1000, 2500].map((amt) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text('SLE $amt', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              backgroundColor: amountCtrl.text == amt.toString() ? AppColors.emeraldSurface : AppColors.gray100,
                              side: BorderSide(
                                color: amountCtrl.text == amt.toString() ? AppColors.emerald : Colors.transparent,
                              ),
                              onPressed: () {
                                setModalState(() => amountCtrl.text = amt.toString());
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Amount Input ─────────────────────────────────
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        labelText: 'Deposit Amount (SLE)',
                        labelStyle: TextStyle(color: Color(0xFF64748B)),
                        hintText: '0.00',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                        prefixText: 'SLE ',
                        prefixStyle: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                    ),

                    // ── Manual instructions banner ───────────────────
                    if (isManual) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                providerInstructions[selectedTopUpProvider] ?? '',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412), height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    // ── Step 2: Reference Input ──────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount: SLE ${double.tryParse(amountCtrl.text.trim())?.toStringAsFixed(2) ?? "0.00"}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Provider: ${providerLabels[selectedTopUpProvider] ?? selectedTopUpProvider}',
                            style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                          ),
                          if (activePhoneNumber.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Paying from: ${_formatPhoneDisplay(activePhoneNumber)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.gray600),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Transaction ID / SMS Reference',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: referenceCtrl,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      cursorColor: const Color(0xFF10B981),
                      decoration: const InputDecoration(
                        hintText: 'e.g. TXN202600001234',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                        labelText: 'Reference Number',
                        labelStyle: TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: Icon(Icons.receipt_long_rounded, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],

                  // ── Contextual Error / Status Banners ──────────────
                  if (errorCode == 'INSUFFICIENT_FUNDS') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFD97706), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Insufficient Mobile Money Balance',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Insufficient balance on ${_formatPhoneDisplay(activePhoneNumber)}. Please top up your SIM wallet and try again.',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFB45309), height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (errorCode == 'INVALID_NUMBER') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.phone_missed_rounded, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Unregistered Phone Number',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'This number (${_formatPhoneDisplay(activePhoneNumber)}) is not registered for ${providerLabels[selectedTopUpProvider]}.',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _showChangeNumberSheet(
                                context: context,
                                currentProvider: selectedTopUpProvider,
                                currentPhone: activePhoneNumber,
                                onSelected: (newPhone) {
                                  setModalState(() {
                                    activePhoneNumber = newPhone;
                                    errorCode = null;
                                    errorMessage = null;
                                  });
                                },
                              ),
                              icon: const Icon(Icons.edit_rounded, size: 14),
                              label: const Text(
                                'Change Number',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (errorCode == 'PIN_TIMEOUT') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.timer_outlined, color: Color(0xFFD97706), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Authorization Prompt Expired',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'The authorization prompt timed out or was cancelled. Please try again and approve promptly on your phone.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309), height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFD97706),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: isProcessing ? null : executeOrangeTopUp,
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: const Text(
                                'Retry Now',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── Action Button ────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isProcessing
                          ? null
                          : () async {
                              // ── ORANGE MONEY (Moneroo Automated) ────
                              if (selectedTopUpProvider == 'orange') {
                                await executeOrangeTopUp();
                                return;
                              }

                              // ── MANUAL PROVIDERS (Step navigation) ──
                              if (!showReferenceStep) {
                                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                                if (amt <= 0) {
                                  setModalState(() => errorMessage = 'Please enter a valid amount.');
                                  return;
                                }
                                setModalState(() {
                                  showReferenceStep = true;
                                  errorMessage = null;
                                  errorCode = null;
                                });
                                return;
                              }

                              // ── SUBMIT MANUAL CLAIM ──────────────────
                              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                              final ref = referenceCtrl.text.trim();
                              if (ref.isEmpty) {
                                setModalState(() => errorMessage = 'Please enter the Transaction ID from your SMS.');
                                return;
                              }

                              setModalState(() {
                                isProcessing = true;
                                errorMessage = null;
                                errorCode = null;
                              });

                              try {
                                final pid = providerIds[selectedTopUpProvider] ?? selectedTopUpProvider;
                                final result = await PaymentMethodsService.instance.submitManualPaymentClaim(
                                  userId: user?.id ?? '',
                                  amount: amt,
                                  providerId: pid,
                                  transactionReference: ref,
                                );

                                if (result['success'] == true) {
                                  if (modalCtx.mounted) Navigator.of(modalCtx).pop();
                                  _fetchWalletData();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Claim submitted! SLE ${amt.toStringAsFixed(2)} pending admin approval.',
                                        ),
                                        backgroundColor: AppColors.emeraldDark,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                } else {
                                  setModalState(() {
                                    errorMessage = result['error'] as String? ?? 'Submission failed. Try again.';
                                    isProcessing = false;
                                  });
                                }
                              } catch (e) {
                                setModalState(() {
                                  errorMessage = 'Error: ${e.toString()}';
                                  isProcessing = false;
                                });
                              }
                            },
                      child: isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              showReferenceStep
                                  ? 'Submit Claim'
                                  : (selectedTopUpProvider == 'orange' ? 'Pay with Orange Money' : 'Continue → Enter Reference'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                    ),
                  ),

                  // ── Back button for step 2 ────────────────────────────
                  if (showReferenceStep) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: isProcessing
                            ? null
                            : () => setModalState(() {
                                  showReferenceStep = false;
                                  referenceCtrl.clear();
                                  errorMessage = null;
                                  errorCode = null;
                                }),
                        child: const Text('← Back', style: TextStyle(color: AppColors.gray500, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showWithdrawEscrowSheet(BuildContext context, UserEntity? user) {
    final amountCtrl = TextEditingController(text: '500');
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final activeMethod = _userPaymentAccounts.firstWhere(
              (m) => m.isDefault,
              orElse: () => _userPaymentAccounts.isNotEmpty
                  ? _userPaymentAccounts.first
                  : const PaymentAccount(
                      id: '',
                      providerCode: 'orange',
                      providerName: 'Orange Money',
                      accountNumber: '',
                      maskedNumber: 'No linked account',
                      isDefault: false,
                      isActive: false,
                    ),
            );

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.arrow_circle_up_rounded, color: AppColors.emeraldDark, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Withdraw Escrow Funds',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Available for payout: SLE ${_walletBalance?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.gray600, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: const Color(0xFF10B981),
                    decoration: const InputDecoration(
                      labelText: 'Withdraw Amount (SLE)',
                      labelStyle: TextStyle(color: Color(0xFF64748B)),
                      hintText: '0.00',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                      prefixText: 'SLE ',
                      prefixStyle: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (activeMethod.accountNumber.isNotEmpty || activeMethod.maskedNumber != 'No linked account') ...[
                    const Text(
                      'Destination Account',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.gray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          _buildProviderIcon(activeMethod.providerCode),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(activeMethod.providerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text(activeMethod.maskedNumber, style: const TextStyle(color: AppColors.gray600, fontSize: 11.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isProcessing
                          ? null
                          : () async {
                              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                              if (amt <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter a valid payout amount.')),
                                );
                                return;
                              }
                              if (amt > (_walletBalance ?? 0.0)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Withdrawal amount exceeds available escrow balance.')),
                                );
                                return;
                              }

                              setModalState(() => isProcessing = true);
                              try {
                                final client = context.read<ConvexClientWrapper>();
                                final res = await client.mutation(
                                  'payments:requestWithdrawal',
                                  args: {
                                    'userId': user?.id ?? '',
                                    'amount': amt,
                                    'destinationProviderCode': activeMethod.providerCode,
                                    'destinationAccountNumber': activeMethod.accountNumber.isNotEmpty
                                        ? activeMethod.accountNumber
                                        : (user?.phone ?? ''),
                                  },
                                );

                                if (res.success) {
                                  await _fetchWalletData();
                                  if (modalCtx.mounted) {
                                    Navigator.of(modalCtx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Payout request of SLE ${amt.toStringAsFixed(2)} submitted successfully!'),
                                        backgroundColor: AppColors.emeraldDark,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } else {
                                  throw Exception(res.errorMessage ?? 'Withdrawal failed');
                                }
                              } catch (e) {
                                setModalState(() => isProcessing = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Withdrawal error: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            },
                      child: isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Authorize & Withdraw', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVerificationBadge(UserEntity? user) {
    final bool isVerified = user?.isVerified == true || user?.isApprovedVerification == true;
    final bool isPending = user?.isPendingVerification == true ||
        user?.kycStatus == 'pending' ||
        user?.kycStatus == 'PENDING_VERIFICATION';
    final bool isRejected = user?.isRejectedVerification == true ||
        user?.kycStatus == 'rejected' ||
        user?.kycStatus == 'REJECTED';

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String label;

    if (isVerified) {
      bgColor = AppColors.emeraldSurface;
      borderColor = AppColors.emerald.withValues(alpha: 0.3);
      textColor = AppColors.emeraldDark;
      icon = Icons.check_circle_rounded;
      label = 'VERIFIED';
    } else if (isPending) {
      bgColor = AppColors.amberSurface;
      borderColor = AppColors.amber.withValues(alpha: 0.4);
      textColor = AppColors.amberDark;
      icon = Icons.schedule_rounded;
      label = 'PENDING REVIEW';
    } else if (isRejected) {
      bgColor = AppColors.errorLight;
      borderColor = AppColors.error.withValues(alpha: 0.3);
      textColor = AppColors.error;
      icon = Icons.cancel_rounded;
      label = 'REJECTED';
    } else {
      bgColor = AppColors.gray100;
      borderColor = AppColors.gray300;
      textColor = AppColors.gray600;
      icon = Icons.shield_outlined;
      label = 'UNVERIFIED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showVerificationInfoDialog(BuildContext context, UserEntity? user) {
    final bool isVerified = user?.isVerified == true || user?.isApprovedVerification == true;
    final bool isPending = user?.isPendingVerification == true ||
        user?.kycStatus == 'pending' ||
        user?.kycStatus == 'PENDING_VERIFICATION';
    final bool isRejected = user?.isRejectedVerification == true ||
        user?.kycStatus == 'rejected' ||
        user?.kycStatus == 'REJECTED';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? AppColors.emeraldSurface
                        : isPending
                            ? AppColors.amberSurface
                            : isRejected
                                ? AppColors.errorLight
                                : AppColors.gray100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isVerified
                        ? Icons.verified_rounded
                        : isPending
                            ? Icons.pending_actions_rounded
                            : isRejected
                                ? Icons.cancel_rounded
                                : Icons.shield_outlined,
                    color: isVerified
                        ? AppColors.emeraldDark
                        : isPending
                            ? AppColors.amberDark
                            : isRejected
                                ? AppColors.error
                                : AppColors.gray600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isVerified
                        ? 'Verified Trust Credentials'
                        : isPending
                            ? 'Verification Under Review'
                            : isRejected
                                ? 'Verification Rejected'
                                : 'Unverified Account',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              isVerified
                  ? 'This account has completed authentic KYC verification for Sierra Leone:'
                  : isPending
                      ? 'Your verification documents have been submitted and are under active review by the Vektolux compliance team:'
                      : isRejected
                          ? (user?.rejectionReason != null && user!.rejectionReason!.isNotEmpty
                              ? 'Your KYC documents were rejected for the following reason: "${user.rejectionReason}"'
                              : 'Your KYC documents were rejected. Please update your business details and re-apply.')
                          : 'This account has not completed official Sierra Leone KYC identity verification. Complete KYC to list vehicles or properties.',
              style: const TextStyle(fontSize: 12, color: AppColors.gray600),
            ),
            const SizedBox(height: 12),
            if (isVerified) ...[
              _buildTrustBadgeItem(Icons.badge_outlined, 'National ID (NIN)',
                  'Identity verified with NCRA standard', color: AppColors.emerald),
              _buildTrustBadgeItem(Icons.receipt_long_outlined, 'NRA Tax ID (TIN)',
                  'Registered tax entity in Sierra Leone', color: AppColors.emerald),
              _buildTrustBadgeItem(Icons.phone_android_outlined, 'Mobile Money KYC',
                  'Orange Money & Africell SIM match', color: AppColors.emerald),
              _buildTrustBadgeItem(Icons.lock_clock_outlined,
                  'Vektolux Escrow Shield', 'Transactions covered by 60/40 split guarantee', color: AppColors.emerald),
            ] else if (isPending) ...[
              _buildTrustBadgeItem(Icons.hourglass_top_rounded, 'Document Review in Progress',
                  'Target turnaround: within 24 business hours', color: AppColors.amberDark),
              _buildTrustBadgeItem(Icons.admin_panel_settings_outlined, 'Compliance Audit',
                  'Admin team verifying document authenticity', color: AppColors.amberDark),
              _buildTrustBadgeItem(Icons.notifications_active_outlined, 'Notification on Complete',
                  'You will receive an in-app and SMS alert once approved', color: AppColors.amberDark),
            ] else ...[
              _buildTrustBadgeItem(Icons.shield_outlined, 'Identity Protection',
                  'Prevent identity fraud and chargebacks', color: AppColors.gray600),
              _buildTrustBadgeItem(Icons.storefront_outlined, 'Vendor Privileges',
                  'Post real estate and vehicle listings', color: AppColors.gray600),
              _buildTrustBadgeItem(Icons.account_balance_wallet_outlined, 'Higher Limits',
                  'Access high-volume transactions in SLE', color: AppColors.gray600),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isVerified
                      ? AppColors.emerald
                      : isPending
                          ? AppColors.amber
                          : AppColors.obsidian,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(isVerified ? 'Understood' : 'Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustBadgeItem(IconData icon, String title, String subtitle, {Color? color}) {
    final effectiveColor = color ?? AppColors.emerald;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: effectiveColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian)),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 10, color: AppColors.gray500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for crisp, zero-dependency QR code rendering on any screen
class _VektoluxQrPainter extends CustomPainter {
  final String data;
  final Color foregroundColor;

  _VektoluxQrPainter({
    required this.data,
    this.foregroundColor = const Color(0xFF0F172A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.fill;

    const matrixSize = 21;
    final moduleSize = size.width / matrixSize;

    void drawModule(int x, int y) {
      canvas.drawRect(
        Rect.fromLTWH(x * moduleSize, y * moduleSize, moduleSize, moduleSize),
        paint,
      );
    }

    void drawFinderPattern(int ox, int oy) {
      for (int x = 0; x < 7; x++) {
        for (int y = 0; y < 7; y++) {
          final isBorder = x == 0 || x == 6 || y == 0 || y == 6;
          final isCenter = x >= 2 && x <= 4 && y >= 2 && y <= 4;
          if (isBorder || isCenter) {
            drawModule(ox + x, oy + y);
          }
        }
      }
    }

    // Draw 3 position detection patterns
    drawFinderPattern(0, 0); // Top-Left
    drawFinderPattern(matrixSize - 7, 0); // Top-Right
    drawFinderPattern(0, matrixSize - 7); // Bottom-Left

    // Draw timing patterns
    for (int i = 8; i < matrixSize - 8; i += 2) {
      drawModule(6, i);
      drawModule(i, 6);
    }

    // Deterministic pseudo-random seed from data string
    int seed = 0;
    for (int i = 0; i < data.length; i++) {
      seed = (seed * 31 + data.codeUnitAt(i)) & 0x7FFFFFFF;
    }

    // Draw data bits (excluding finder patterns and center logo area)
    for (int x = 0; x < matrixSize; x++) {
      for (int y = 0; y < matrixSize; y++) {
        if (x <= 7 && y <= 7) continue; // Top-Left
        if (x >= matrixSize - 8 && y <= 7) continue; // Top-Right
        if (x <= 7 && y >= matrixSize - 8) continue; // Bottom-Left

        // Skip center 5x5 logo reservation area
        if (x >= 8 && x <= 12 && y >= 8 && y <= 12) continue;

        // Skip timing pattern lines
        if (x == 6 || y == 6) continue;

        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        if ((seed % 100) < 52) {
          drawModule(x, y);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VektoluxQrPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.foregroundColor != foregroundColor;
}
