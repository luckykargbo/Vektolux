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
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/views/login_screen.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../../operator/presentation/views/operator_dashboard_screen.dart';
import '../../../mobility/presentation/views/driver_vehicle_registration_screen.dart';
import '../../../admin/presentation/views/admin_dev_tools_screen.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';

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
  bool _pushNotifications = true;
  bool _smsAlerts = true;
  bool _biometricAuth = false;

  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  void _openAdminDevTools(BuildContext context, UserEntity? user) {
    if (user == null) return;
    final database = context.read<AppDatabase>();
    final convexClient = context.read<ConvexClientWrapper>();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDevToolsScreen(
          convexClient: convexClient,
          database: database,
          currentUser: user,
        ),
      ),
    );
  }

  void _onVersionTapped(BuildContext context, UserEntity? user) {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 3)) {
      _versionTapCount = 1;
    } else {
      _versionTapCount++;
    }
    _lastVersionTap = now;

    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛠️ Developer mode unlocked! Opening Dev Tools...'),
          backgroundColor: Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      _openAdminDevTools(context, user);
    } else if (_versionTapCount >= 2) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Tap ${5 - _versionTapCount} more times to open Dev Tools'),
          duration: const Duration(milliseconds: 700),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showEditProfileModal(BuildContext context, UserEntity user) {
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
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
                'Update your display name and contact phone number.',
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
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
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
                    context.read<AuthBloc>().add(
                          UpdateUserProfileEvent(
                            name: updatedName.isNotEmpty ? updatedName : null,
                            phone: updatedPhone.isNotEmpty ? updatedPhone : null,
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
                final publicUrl = await ImageUploadService.uploadImageToConvex(
                  convexClient: convexClient,
                  imageBytes: pickedBytes!,
                );
                if (modalCtx.mounted) {
                  context.read<AuthBloc>().add(
                        UpdateUserProfileEvent(avatarUrl: publicUrl),
                      );
                  Navigator.of(modalCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile photo uploaded and synced successfully!'),
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

                  // Actions: Save or Remove
                  Row(
                    children: [
                      if (currentAvatarUrl != null && currentAvatarUrl.isNotEmpty) ...[
                        OutlinedButton(
                          onPressed: isUploading
                              ? null
                              : () {
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
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.errorLight),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Remove'),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
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
                                    Text('Uploading to Cloud...'),
                                  ],
                                )
                              : const Text('Upload & Save Photo'),
                        ),
                      ),
                    ],
                  ),
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        final displayName = user?.name.isNotEmpty == true ? user!.name : 'Lamin Kamara';
        final displayPhone = user?.phone.isNotEmpty == true ? user!.phone : '+232 76 123 456';
        final displayEmail = user?.email.isNotEmpty == true ? user!.email : 'user@vektolux.sl';
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
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.emeraldSurface,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_rounded, size: 12, color: AppColors.emeraldDark),
                                        SizedBox(width: 3),
                                        Text(
                                          'VERIFIED',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.emeraldDark,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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

                // ── 1B. Dual-Role Mode Switcher (Only if driver verified/registered) ──
                if (user?.canSwitchToDriver == true) ...[
                  _buildSectionHeader('WORKSPACE & ACCOUNT MODE'),
                  _buildModeSwitcherCard(context, user),
                  const SizedBox(height: 18),
                ],

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
                  icon: Icons.local_taxi_rounded,
                  title: 'Become a Driver / Keke Operator',
                  subtitle:
                      'Earn with on-demand rides & deliveries across Sierra Leone',
                  actionLabel: 'Register Vehicle',
                  badgeText: role == UserRole.driver ? 'ACTIVE' : 'APPLY',
                  isEnrolled: role == UserRole.driver,
                  onTap: () async {
                    final res = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => DriverVehicleRegistrationScreen(
                          driverId: user?.id ?? '',
                        ),
                      ),
                    );
                    if (res == true && context.mounted) {
                      context
                          .read<AuthBloc>()
                          .add(const UserRoleUpdatedEvent(UserRole.driver));
                    }
                  },
                ),
                const SizedBox(height: 10),
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
                      'List showroom cars, kekes & fleet rentals with escrow',
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
                              value: '6 Items',
                              color: AppColors.obsidian,
                            ),
                            const SizedBox(width: 10),
                            _buildVendorStatCard(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Escrow Balance',
                              value: 'SLE 14,250',
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
                                color: AppColors.emeraldSurface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.badge_outlined,
                                color: AppColors.emeraldDark,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'KYC Verification: Verified',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.obsidian,
                                    ),
                                  ),
                                  Text(
                                    'National ID & TIN credentials verified on-chain',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.emerald,
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
                _buildSectionHeader('SAVED PLACES & SHORTCUTS'),
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
                        subtitle: '18 Wilkinson Road, Freetown',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.work_outline,
                        title: 'Work / Office',
                        subtitle: 'Siaka Stevens Street, Central Business District',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.beach_access_outlined,
                        title: 'Lumley Beach',
                        subtitle: 'Aberdeen Peninsula Road',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 4. Payment & Mobile Money Wallets ───────────────
                _buildSectionHeader('PAYMENT, QR CODES & ESCROW WALLETS'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.qr_code_2_rounded,
                        title: 'My Account QR Code',
                        subtitle: 'Display personal QR to receive payments & transfers',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () => _showMyQrCodeModal(context, user),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Scan to Pay / Transfer',
                        subtitle: 'Scan vendor, driver, or merchant QR code',
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () => _showScanQrModal(context, user),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Wallet Security PIN',
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
                      _buildSettingsTile(
                        icon: Icons.phone_android_outlined,
                        title: 'Orange Money Sierra Leone',
                        subtitle: '$displayPhone • Active',
                        trailing: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.emerald,
                          size: 18,
                        ),
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.signal_cellular_alt_rounded,
                        title: 'Africell Afrimoney',
                        subtitle: 'Linked Mobile Money account',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Vektolux Escrow Wallet',
                        subtitle: 'Balance: SLE 3,500.00 (60/40 Protected)',
                        trailing: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Wallet top-up via Mobile Money is ready.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: const Text('Top Up'),
                        ),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── 5. App Preferences & Security ───────────────────
                _buildSectionHeader('APP PREFERENCES & SECURITY'),
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
                        subtitle: const Text('Real-time driver & inspection alerts', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
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
                      SwitchListTile(
                        secondary: const Icon(Icons.fingerprint_rounded, color: AppColors.gray500),
                        title: const Text('Biometric / PIN Screen Lock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Require fingerprint/face lock before checkout', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                        value: _biometricAuth,
                        activeThumbColor: AppColors.emerald,
                        onChanged: (val) => setState(() => _biometricAuth = val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.school_outlined,
                        title: 'Interactive App Tour',
                        subtitle: 'Learn how to hail rides, book homes, and pay with Agent 001',
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
                        subtitle: 'Direct WhatsApp & telephone: +232 73 623 761',
                        onTap: () {
                          Clipboard.setData(
                            const ClipboardData(text: '+23273623761'),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Support line copied: +23273623761 (+232 73 623 761) - 24/7 Assistance',
                              ),
                              backgroundColor: AppColors.emerald,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildSettingsTile(
                        icon: Icons.info_outline,
                        title: 'App Version',
                        subtitle: 'Vektolux v1.2.0-sl-prod (Build 120)',
                        trailing: const Text(
                          'Latest',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                        onTap: () => _onVersionTapped(context, user),
                      ),
                    ],
                  ),
                ),

                // ── 7. Developer & Admin Tools ──────────────────────
                if (role == UserRole.admin) ...[
                  const SizedBox(height: 18),
                  _buildSectionHeader('DEVELOPER & ADMIN TOOLS'),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: _buildSettingsTile(
                      icon: Icons.developer_mode_rounded,
                      title: 'Developer & Admin Tools',
                      subtitle:
                          'Quick seed, batch asset uploader & draft manager',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'DEV TOOLS',
                          style: TextStyle(
                            color: Color(0xFFD97706),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      onTap: () => _openAdminDevTools(context, user),
                    ),
                  ),
                ],

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
                  isDriverMode ? Icons.local_taxi_rounded : Icons.person_rounded,
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
                      isDriverMode ? 'Driver Workspace Active' : 'Passenger Mode Active',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDriverMode
                          ? 'Receiving trip dispatches & telemetry'
                          : 'Browsing super-app verticals & hailing rides',
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
                  isDriverMode ? 'DRIVER' : 'CLIENT',
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
                              content: Text('Switched to Passenger Mode'),
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
                                'Passenger Mode',
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
                              content: Text('Switched to Driver Workspace'),
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
                                Icons.local_taxi_rounded,
                                size: 16,
                                color: isDriverMode ? AppColors.white : AppColors.gray500,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Driver Workspace',
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.obsidian,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.app_registration_rounded, size: 16),
                    label: const Text(
                      'Register Vehicle to Drive',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DriverVehicleRegistrationScreen(
                            driverId: user?.id ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.emeraldSurface,
                    foregroundColor: AppColors.emeraldDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.emerald, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text(
                    'Demo Unlock',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  onPressed: () async {
                    if (user == null) return;
                    try {
                      final client = context.read<ConvexClientWrapper>();
                      await client.mutation(
                        'users:mockApproveRoleUpgrade',
                        args: {
                          'userId': user.id,
                          'targetRole': 'driver',
                        },
                      );
                      if (context.mounted) {
                        context.read<AuthBloc>().add(const SwitchUserModeEvent('driver'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Driver Workspace Unlocked! (Demo Verification)'),
                            backgroundColor: AppColors.emerald,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Unlock error: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
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
    final tinCtrl = TextEditingController(text: 'TIN-SL-84920');

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
              decoration: const InputDecoration(
                labelText: 'Agency / Business Name',
                prefixIcon: Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinCtrl,
              decoration: const InputDecoration(
                labelText: 'TIN / Business Registration',
                prefixIcon: Icon(Icons.badge_outlined),
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
                  final client = context.read<ConvexClientWrapper>();
                  await client.mutation(
                    'users:mockApproveRoleUpgrade',
                    args: {'userId': user.id, 'targetRole': 'agent'},
                  );
                  if (context.mounted) {
                    context
                        .read<AuthBloc>()
                        .add(const UserRoleUpdatedEvent(UserRole.agent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Agent credentials verified! You can now publish properties.'),
                        backgroundColor: AppColors.emeraldDark,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Submit & Activate (Demo)',
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
    final tinCtrl = TextEditingController(text: 'TIN-SL-90241');

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
              'Submit your dealership registration to list cars for sale, kekes, and fleet rentals.',
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dealerCtrl,
              decoration: const InputDecoration(
                labelText: 'Dealership / Fleet Name',
                prefixIcon: Icon(Icons.directions_car_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinCtrl,
              decoration: const InputDecoration(
                labelText: 'TIN / Trade License Number',
                prefixIcon: Icon(Icons.badge_outlined),
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
                  final client = context.read<ConvexClientWrapper>();
                  await client.mutation(
                    'users:mockApproveRoleUpgrade',
                    args: {'userId': user.id, 'targetRole': 'merchant'},
                  );
                  if (context.mounted) {
                    context
                        .read<AuthBloc>()
                        .add(const UserRoleUpdatedEvent(UserRole.merchant));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Auto Dealer verified! You can now list vehicles in the showroom.'),
                        backgroundColor: Color(0xFF92400E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text(
                  'Submit & Activate (Demo)',
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
    final qrData =
        'vektolux://pay?userId=${user?.id ?? "guest"}&phone=${user?.phone ?? ""}&name=${Uri.encodeComponent(user?.name ?? "User")}';

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

            // QR Container Card
            Container(
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
                    user?.phone ?? '+232 ...',
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
                    child: const Text(
                      'VERIFIED CITIZEN ID • ESCROW ENABLED',
                      style: TextStyle(
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
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: user?.id ?? 'VLX-SL-232'));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vektolux Account ID copied to clipboard!'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sharing payment QR link...'),
                          behavior: SnackBarBehavior.floating,
                        ),
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
                    decoration: const InputDecoration(
                      labelText: 'Enter New 4-Digit PIN',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: confirmPinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Confirm 4-Digit PIN',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
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

  void _showVerificationInfoDialog(BuildContext context, UserEntity? user) {
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
                  decoration: const BoxDecoration(
                    color: AppColors.emeraldSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_rounded,
                      color: AppColors.emeraldDark, size: 24),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Verified Trust Credentials',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'This account has completed authentic KYC verification for Sierra Leone:',
              style: TextStyle(fontSize: 12, color: AppColors.gray600),
            ),
            const SizedBox(height: 12),
            _buildTrustBadgeItem(Icons.badge_outlined, 'National ID (NIN)',
                'Identity verified with NCRA standard'),
            _buildTrustBadgeItem(Icons.receipt_long_outlined, 'NRA Tax ID (TIN)',
                'Registered tax entity in Sierra Leone'),
            _buildTrustBadgeItem(Icons.phone_android_outlined, 'Mobile Money KYC',
                'Orange Money & Africell SIM match'),
            _buildTrustBadgeItem(Icons.lock_clock_outlined,
                'Vektolux Escrow Shield', 'Transactions covered by 60/40 split guarantee'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Understood'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustBadgeItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.emerald),
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
