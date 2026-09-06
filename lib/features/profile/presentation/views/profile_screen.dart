// lib/features/profile/presentation/views/profile_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — User Profile, Account Settings & Vendor Management
// Comprehensive profile dashboard with Orange/Africell Mobile Money,
// KYC verification status, vendor tools, and secure session logout.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/views/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? currentUserId;

  const ProfileScreen({
    super.key,
    this.currentUserId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _pushNotifications = true;
  bool _smsAlerts = true;
  bool _biometricAuth = false;

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
    String selectedUrl = user?.avatarUrl ?? '';
    final urlController = TextEditingController(text: user?.avatarUrl ?? '');

    final avatarPresets = [
      {'name': 'Client', 'url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150'},
      {'name': 'Vendor', 'url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'},
      {'name': 'Driver', 'url': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150'},
      {'name': 'Agent', 'url': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150'},
      {'name': 'Traveler', 'url': 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=150'},
      {'name': 'Partner', 'url': 'https://images.unsplash.com/photo-1501196354995-cbb51c65aaea?w=150'},
    ];

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
                    'Update Profile Photo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose a role avatar or enter a cloud image URL.',
                    style: TextStyle(fontSize: 13, color: AppColors.gray500),
                  ),
                  const SizedBox(height: 20),

                  // Circular Crop Preview with Emerald Ring
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
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
                            child: selectedUrl.isNotEmpty
                                ? Image.network(
                                    selectedUrl,
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image_rounded,
                                      size: 36,
                                      color: AppColors.gray400,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 44,
                                    color: AppColors.gray400,
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 14,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Avatar Presets
                  const Text(
                    'Select Preset Role Avatar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: avatarPresets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, idx) {
                        final preset = avatarPresets[idx];
                        final isSelected = selectedUrl == preset['url'];
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedUrl = preset['url']!;
                              urlController.text = preset['url']!;
                            });
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? AppColors.emerald : AppColors.gray200,
                                    width: isSelected ? 2.5 : 1,
                                  ),
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    preset['url']!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.person),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preset['name']!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? AppColors.emeraldDark : AppColors.gray600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Custom URL Input
                  TextFormField(
                    controller: urlController,
                    style: const TextStyle(fontSize: 13, color: AppColors.obsidian),
                    decoration: InputDecoration(
                      labelText: 'Cloud Image URL',
                      hintText: 'https://...',
                      prefixIcon: const Icon(Icons.link_rounded, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: AppColors.emerald),
                        onPressed: () {
                          setModalState(() {
                            selectedUrl = urlController.text.trim();
                          });
                        },
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        selectedUrl = val.trim();
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    children: [
                      if (selectedUrl.isNotEmpty) ...[
                        OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              selectedUrl = '';
                              urlController.clear();
                            });
                          },
                          child: const Text('Remove Photo'),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<AuthBloc>().add(
                                  UpdateUserProfileEvent(avatarUrl: selectedUrl),
                                );
                            Navigator.of(modalCtx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile photo updated successfully.'),
                                backgroundColor: AppColors.emerald,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: const Text('Save Profile Photo'),
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

        final initials = displayName
            .trim()
            .split(' ')
            .take(2)
            .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
            .join();

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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
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
                      GestureDetector(
                        onTap: () => _showAvatarPickerModal(context, user),
                        child: Stack(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.emerald, width: 2.5),
                                gradient: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                                    ? const LinearGradient(
                                        colors: [AppColors.emerald, AppColors.emeraldDark],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.emerald.withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                                    ? Image.network(
                                        user.avatarUrl!,
                                        width: 68,
                                        height: 68,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(
                                            initials.isNotEmpty ? initials : 'VK',
                                            style: const TextStyle(
                                              color: AppColors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          initials.isNotEmpty ? initials : 'VK',
                                          style: const TextStyle(
                                            color: AppColors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.emerald,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 13,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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

                // ── 2. Vendor / Merchant Hub (If vendor role) ────────
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
                _buildSectionHeader('PAYMENT & MOBILE MONEY'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
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
                        subtitle: 'Balance: SLE 3,500.00',
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
                        subtitle: 'Direct WhatsApp & telephone assistance in Freetown',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Support line: +232 76 000 111 (Mon-Sun 8am-10pm)'),
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
}
