// lib/features/profile/presentation/views/account_profile_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Settings → Account & Profile.
// Verified profile header, contact details, Account PIN, biometric login and the
// account deletion request. Every change goes through the server, which decides:
//   • the name is never editable here (the server also refuses it once verified);
//   • the phone changes via users:linkPhoneNumber (PIN-protected, uniqueness-checked);
//   • the PIN is the existing hashed PIN (payments:setWalletPin), never shown or stored here;
//   • biometric login only asks the OS for a success/failure (lib/core/services/biometric_login_service.dart);
//   • deletion is a 30-day pending request (users:requestAccountDeletion), never immediate.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/biometric_login_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/views/login_screen.dart';

const _gutter = 16.0;
const _radius = 18.0;
const _danger = Color(0xFFDC2626);
const _dangerSurface = Color(0xFFFEF2F2);

/// Server view of the signed-in user's own account (users:getUserProfile, owner-only fields).
class _AccountProfile {
  final String name;
  final String? professionalTitle;
  final bool identityVerified;
  final DateTime? memberSince;
  final String? avatarUrl;
  final String phone;
  final String email;

  const _AccountProfile({
    required this.name,
    required this.professionalTitle,
    required this.identityVerified,
    required this.memberSince,
    required this.avatarUrl,
    required this.phone,
    required this.email,
  });

  factory _AccountProfile.fromJson(Map<String, dynamic> j, UserEntity fallback) {
    final since = j['memberSince'];
    final title = (j['professionalTitle'] as String?)?.trim();
    final avatar = (j['avatarUrl'] as String?)?.trim();
    return _AccountProfile(
      name: (j['name'] as String?)?.trim().isNotEmpty == true ? (j['name'] as String).trim() : fallback.name,
      professionalTitle: title == null || title.isEmpty ? null : title,
      identityVerified: j['identityVerified'] == true,
      memberSince: since is num ? DateTime.fromMillisecondsSinceEpoch(since.toInt()) : null,
      avatarUrl: avatar == null || avatar.isEmpty ? null : avatar,
      phone: (j['phone'] as String?) ?? fallback.phone,
      email: (j['email'] as String?) ?? fallback.email,
    );
  }

  /// Before the server answers, show what the signed-in session already knows.
  factory _AccountProfile.fromSession(UserEntity u) => _AccountProfile(
        name: u.name,
        professionalTitle: null,
        identityVerified: u.isVerified || u.isApprovedVerification,
        memberSince: null,
        avatarUrl: u.avatarUrl?.trim().isNotEmpty == true ? u.avatarUrl : null,
        phone: u.phone,
        email: u.email,
      );

  bool get hasPhone {
    final p = phone.trim();
    return p.isNotEmpty && p != '+232' && !p.startsWith('0000000000');
  }

  /// Accounts created through Apple/Google without a shared email get an internal placeholder.
  bool get hasRealEmail {
    final e = email.trim().toLowerCase();
    return e.isNotEmpty && !e.endsWith('.invalid') && !e.startsWith('deleted_');
  }
}

/// The one Account & Profile screen, opened from the client Account tab and from the agent
/// Settings. It always acts on the signed-in account.
class AccountProfileScreen extends StatefulWidget {
  final BiometricLoginService? biometrics;

  /// Opens the phone-change sheet as soon as the PIN status is known (used by the Account tab's
  /// "Change phone number" link, so there is a single phone-change flow).
  final bool openPhoneChange;

  const AccountProfileScreen({super.key, this.biometrics, this.openPhoneChange = false});

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late final BiometricLoginService _biometrics = widget.biometrics ?? BiometricLoginService();

  _AccountProfile? _profile;
  bool? _hasPin; // null = not known yet
  bool _pinStatusFailed = false;
  List<BiometricMethod> _methods = const [];
  bool _biometricEnabled = false;
  bool _biometricBusy = false;

  UserEntity? get _user => context.read<AuthBloc>().state.user;

  @override
  void initState() {
    super.initState();
    final user = _user;
    if (user != null) _profile = _AccountProfile.fromSession(user);
    _loadProfile();
    final pinStatus = _loadPinStatus();
    _loadBiometrics();
    if (widget.openPhoneChange) {
      pinStatus.whenComplete(() {
        if (mounted) _changePhone();
      });
    }
  }

  Future<void> _loadProfile() async {
    final user = _user;
    if (user == null) return;
    final res = await context.read<ConvexClientWrapper>().query('users:getUserProfile', args: {'userId': user.id});
    if (!mounted || !res.success || res.value is! Map) return;
    setState(() => _profile = _AccountProfile.fromJson(Map<String, dynamic>.from(res.value as Map), user));
  }

  Future<void> _loadPinStatus() async {
    final user = _user;
    if (user == null) return;
    setState(() => _pinStatusFailed = false);
    final res = await context
        .read<ConvexClientWrapper>()
        .query('payments:getUserSecurityPinStatus', args: {'userId': user.id});
    if (!mounted) return;
    setState(() {
      if (res.success && res.value is Map) {
        _hasPin = (res.value as Map)['hasPin'] == true;
      } else {
        _pinStatusFailed = true;
      }
    });
  }

  Future<void> _loadBiometrics() async {
    final user = _user;
    if (user == null) return;
    final methods = await _biometrics.availableMethods();
    final enabled = methods.isNotEmpty && await _biometrics.isEnabled(user.id);
    if (!mounted) return;
    setState(() {
      _methods = methods;
      _biometricEnabled = enabled;
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _danger : AppColors.obsidian,
      ));
  }

  // ─── Actions ──────────────────────────────────────────────────────

  Future<void> _changePhone() async {
    final user = _user;
    final profile = _profile;
    if (user == null || profile == null) return;
    if (_hasPin == null) {
      _snack('Checking your PIN status. Try again in a moment.', error: true);
      _loadPinStatus();
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PhoneChangeSheet(
        userId: user.id,
        requirePin: profile.hasPhone && _hasPin == true,
        isFirstNumber: !profile.hasPhone,
        repository: context.read<AuthRepository>(),
      ),
    );
    if (changed != true || !mounted) return;
    context.read<AuthBloc>().add(const RefreshUserSessionEvent());
    await _loadProfile();
    _snack('Phone number updated.');
  }

  Future<void> _setOrChangePin() async {
    final user = _user;
    if (user == null) return;
    if (_hasPin == null) {
      _snack('Checking your PIN status. Try again in a moment.', error: true);
      _loadPinStatus();
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PinSheet(
        userId: user.id,
        hasPin: _hasPin == true,
        client: context.read<ConvexClientWrapper>(),
      ),
    );
    if (saved != true || !mounted) return;
    final wasSet = _hasPin == true;
    setState(() => _hasPin = true);
    _snack(wasSet ? 'Account PIN changed.' : 'Account PIN set.');
  }

  Future<void> _toggleBiometric(bool enable) async {
    final user = _user;
    if (user == null || _biometricBusy) return;
    setState(() => _biometricBusy = true);
    try {
      if (enable) {
        // Turning it on proves the enrolled biometric works on this device first.
        final ok = await _biometrics.authenticate('Confirm to turn on ${biometricLabel(_methods)} for Vektolux');
        if (!ok) {
          if (mounted) _snack('${biometricLabel(_methods)} was not confirmed. Nothing changed.', error: true);
          return;
        }
      }
      await _biometrics.setEnabled(user.id, enable);
      if (mounted) setState(() => _biometricEnabled = enable);
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final user = _user;
    if (user == null) return;
    if (_hasPin == null) {
      _snack('Checking your PIN status. Try again in a moment.', error: true);
      _loadPinStatus();
      return;
    }
    final scheduledFor = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DeleteAccountSheet(
        userId: user.id,
        requirePin: _hasPin == true,
        client: context.read<ConvexClientWrapper>(),
      ),
    );
    if (scheduledFor == null || !mounted) return;

    // The server has already signed this account out everywhere.
    await _biometrics.setEnabled(user.id, false);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.read<AuthBloc>().add(const LogoutEvent());
    context.read<ConvexClientWrapper>().clearAuth();
    messenger.showSnackBar(SnackBar(
      content: Text(
        'Deletion requested. Your account will be permanently deleted on '
        '${DateFormat('d MMM y').format(scheduledFor)}. Sign in before then to cancel.',
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.obsidian,
      duration: const Duration(seconds: 6),
    ));
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ─── Layout ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        title: const Text('Account & Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: profile == null
          ? const Center(child: Text('Sign in to manage your account.', style: TextStyle(color: AppColors.gray500)))
          : RefreshIndicator(
              color: AppColors.emeraldDark,
              onRefresh: () => Future.wait([_loadProfile(), _loadPinStatus(), _loadBiometrics()]),
              child: ListView(
                key: const Key('account-profile-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(_gutter, 8, _gutter, 28 + MediaQuery.paddingOf(context).bottom),
                children: [
                  _ProfileHeader(profile: profile),
                  const SizedBox(height: 14),
                  _contactCard(profile),
                  const SizedBox(height: 14),
                  _pinCard(),
                  const SizedBox(height: 14),
                  _biometricCard(),
                  const SizedBox(height: 22),
                  _deleteCard(),
                ],
              ),
            ),
    );
  }

  Widget _contactCard(_AccountProfile profile) => _SectionCard(
        icon: Icons.phone_in_talk_outlined,
        title: 'Contact Details',
        subtitle: 'Phone number and email on your account',
        children: [
          _Row(
            key: const Key('account-phone-row'),
            label: 'Phone Number',
            value: profile.hasPhone ? _formatPhone(profile.phone) : 'Not added',
            trailing: _OutlineAction(
              key: const Key('account-change-phone'),
              icon: profile.hasPhone ? Icons.edit_outlined : Icons.add_rounded,
              label: profile.hasPhone ? 'Change' : 'Add',
              onPressed: _changePhone,
            ),
          ),
          if (profile.hasRealEmail) _Row(key: const Key('account-email-row'), label: 'Email', value: profile.email),
        ],
      );

  Widget _pinCard() {
    final String status;
    if (_hasPin == null) {
      status = _pinStatusFailed ? 'Could not load' : 'Checking…';
    } else {
      status = _hasPin! ? 'Set' : 'Not set';
    }
    return _SectionCard(
      icon: Icons.lock_outline_rounded,
      title: 'Account PIN',
      subtitle: 'Your 4-digit PIN protects payments and account changes',
      children: [
        _Row(
          key: const Key('account-pin-row'),
          label: 'PIN Status',
          value: status,
          trailing: _pinStatusFailed
              ? _OutlineAction(icon: Icons.refresh_rounded, label: 'Retry', onPressed: _loadPinStatus)
              : _OutlineAction(
                  key: const Key('account-pin-action'),
                  icon: Icons.lock_rounded,
                  label: _hasPin == true ? 'Change PIN' : 'Set PIN',
                  onPressed: _hasPin == null ? null : _setOrChangePin,
                ),
        ),
      ],
    );
  }

  Widget _biometricCard() {
    final label = biometricLabel(_methods);
    return _SectionCard(
      icon: Icons.fingerprint_rounded,
      title: 'Biometric Login',
      subtitle: _methods.isEmpty
          ? 'Unlock Vektolux with your device biometrics'
          : 'Use $label to unlock Vektolux when you open the app',
      children: [
        if (_methods.isEmpty)
          const _Row(
            key: Key('account-biometric-unavailable'),
            label: 'Not available',
            value: 'This device has no Face ID, Touch ID or fingerprint set up.',
          )
        else
          _Row(
            key: const Key('account-biometric-row'),
            label: label,
            value: _biometricEnabled ? 'Enabled' : 'Not enabled',
            trailing: Switch.adaptive(
              key: const Key('account-biometric-switch'),
              value: _biometricEnabled,
              activeTrackColor: AppColors.emerald,
              onChanged: _biometricBusy ? null : _toggleBiometric,
            ),
          ),
      ],
    );
  }

  Widget _deleteCard() => Container(
        key: const Key('account-delete-card'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              icon: Icons.delete_outline_rounded,
              iconColor: _danger,
              iconBackground: _dangerSurface,
              title: 'Delete Account',
              titleColor: _danger,
              subtitle: 'Your account will be permanently deleted after 30 days. '
                  'Sign in again within 30 days to cancel.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('account-delete-button'),
              onPressed: _requestDeletion,
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _danger,
                side: const BorderSide(color: _danger),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
}

String _formatPhone(String phone) {
  final p = phone.replaceAll(' ', '');
  final m = RegExp(r'^\+232(\d{2})(\d{3})(\d{3})$').firstMatch(p);
  return m == null ? phone : '+232 ${m[1]} ${m[2]} ${m[3]}';
}

// ═══════════════════════════════════════════════════════════════════════
//                              PIECES
// ═══════════════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  final _AccountProfile profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final initials = profile.name.trim().isEmpty
        ? null
        : profile.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      key: const Key('account-profile-header'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.emeraldDark,
            foregroundImage: profile.avatarUrl == null ? null : NetworkImage(profile.avatarUrl!),
            child: initials == null
                ? const Icon(Icons.person_rounded, color: Colors.white, size: 36)
                : Text(initials, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  key: const Key('account-verified-name'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                ),
                const SizedBox(height: 4),
                _IdentityChip(verified: profile.identityVerified),
                if (profile.professionalTitle != null) ...[
                  const SizedBox(height: 6),
                  Text(profile.professionalTitle!,
                      style: const TextStyle(fontSize: 13.5, color: AppColors.gray700, fontWeight: FontWeight.w500)),
                ],
                if (profile.memberSince != null) ...[
                  const SizedBox(height: 2),
                  Text('Member since ${DateFormat('d MMM y').format(profile.memberSince!)}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.gray500)),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.gray400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        profile.identityVerified
                            ? 'Verified name · cannot be edited'
                            : 'Your name is confirmed when your identity is verified',
                        key: const Key('account-name-locked-note'),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.gray500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityChip extends StatelessWidget {
  final bool verified;
  const _IdentityChip({required this.verified});

  @override
  Widget build(BuildContext context) {
    final color = verified ? AppColors.emeraldDark : AppColors.gray500;
    return Container(
      key: Key(verified ? 'account-identity-verified' : 'account-identity-unverified'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: verified ? AppColors.emeraldSurface : AppColors.gray100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.verified_rounded : Icons.shield_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              verified ? 'Verified Identity' : 'Identity not verified',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SectionCard({required this.icon, required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(icon: icon, title: title, subtitle: subtitle),
          for (final child in children) ...[
            const Padding(
              padding: EdgeInsets.only(left: 58, top: 10),
              child: Divider(height: 1, color: AppColors.gray200),
            ),
            Padding(padding: const EdgeInsets.only(left: 58), child: child),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color iconBackground;
  final Color titleColor;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = AppColors.emeraldDark,
    this.iconBackground = AppColors.emeraldSurface,
    this.titleColor = AppColors.obsidian,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: titleColor)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.gray500, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _Row({super.key, required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 13, color: AppColors.gray500)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _OutlineAction({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.emeraldDark,
        side: const BorderSide(color: AppColors.emerald, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 38),
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// Masked numeric PIN input. The value never leaves the sheet except in the server call.
class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;

  const _PinField({super.key, required this.controller, required this.label, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 8, color: AppColors.obsidian),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.gray500),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.6),
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SheetFrame({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.iconColor = AppColors.emeraldDark,
    this.iconBackground = AppColors.emeraldSurface,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.gray300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle(
                icon: icon,
                iconColor: iconColor,
                iconBackground: iconBackground,
                title: title,
                subtitle: subtitle,
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  final String? message;
  const _SheetError(this.message);

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(message!, key: const Key('account-sheet-error'), style: const TextStyle(color: _danger, fontSize: 13)),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final Color color;

  const _PrimaryButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.color = AppColors.emeraldDark,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }
}

// ─── Phone ──────────────────────────────────────────────────────────

class _PhoneChangeSheet extends StatefulWidget {
  final String userId;
  final bool requirePin;
  final bool isFirstNumber;
  final AuthRepository repository;

  const _PhoneChangeSheet({
    required this.userId,
    required this.requirePin,
    required this.isFirstNumber,
    required this.repository,
  });

  @override
  State<_PhoneChangeSheet> createState() => _PhoneChangeSheetState();
}

class _PhoneChangeSheetState extends State<_PhoneChangeSheet> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    var national = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (national.startsWith('0')) national = national.substring(1);
    if (national.length != 8) {
      setState(() => _error = 'Enter a Sierra Leone number, e.g. 076 123 456.');
      return;
    }
    if (widget.requirePin && _pin.text.length != 4) {
      setState(() => _error = 'Enter your 4-digit Account PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.linkPhoneNumber(
        userId: widget.userId,
        phoneNumber: '+232$national',
        currentPin: widget.requirePin ? _pin.text : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _pin.clear();
      setState(() {
        _busy = false;
        _error = e is AuthException ? e.message : 'Could not update your phone number. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      icon: Icons.phone_in_talk_outlined,
      title: widget.isFirstNumber ? 'Add phone number' : 'Change phone number',
      subtitle: widget.requirePin
          ? 'Enter your new Sierra Leone number and confirm with your Account PIN.'
          : 'Enter your Sierra Leone mobile number.',
      children: [
        TextField(
          key: const Key('account-phone-input'),
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d ]')), LengthLimitingTextInputFormatter(12)],
          decoration: InputDecoration(
            labelText: 'New phone number',
            hintText: '076 123 456',
            prefixText: '+232 ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.emerald, width: 1.6),
            ),
          ),
        ),
        if (widget.requirePin) ...[
          const SizedBox(height: 14),
          _PinField(key: const Key('account-phone-pin'), controller: _pin, label: 'Account PIN'),
        ],
        const SizedBox(height: 16),
        _SheetError(_error),
        _PrimaryButton(key: const Key('account-phone-save'), label: 'Save phone number', busy: _busy, onPressed: _submit),
      ],
    );
  }
}

// ─── PIN ────────────────────────────────────────────────────────────

class _PinSheet extends StatefulWidget {
  final String userId;
  final bool hasPin;
  final ConvexClientWrapper client;

  const _PinSheet({required this.userId, required this.hasPin, required this.client});

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.hasPin && _current.text.length != 4) {
      setState(() => _error = 'Enter your current 4-digit PIN.');
      return;
    }
    if (_next.text.length != 4) {
      setState(() => _error = 'Your new PIN must be exactly 4 digits.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'The PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await widget.client.mutation('payments:setWalletPin', args: {
      'userId': widget.userId,
      'pin': _next.text,
      if (widget.hasPin) 'currentPin': _current.text,
    });
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).pop(true);
      return;
    }
    _current.clear();
    setState(() {
      _busy = false;
      _error = res.errorMessage ?? 'Could not save your PIN. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      icon: Icons.lock_outline_rounded,
      title: widget.hasPin ? 'Change Account PIN' : 'Set Account PIN',
      subtitle: 'Your PIN is never shown or stored on this device.',
      children: [
        if (widget.hasPin) ...[
          _PinField(key: const Key('account-pin-current'), controller: _current, label: 'Current PIN', autofocus: true),
          const SizedBox(height: 14),
        ],
        _PinField(key: const Key('account-pin-new'), controller: _next, label: 'New 4-digit PIN', autofocus: !widget.hasPin),
        const SizedBox(height: 14),
        _PinField(key: const Key('account-pin-confirm'), controller: _confirm, label: 'Confirm new PIN'),
        const SizedBox(height: 16),
        _SheetError(_error),
        _PrimaryButton(key: const Key('account-pin-save'), label: 'Save PIN', busy: _busy, onPressed: _submit),
      ],
    );
  }
}

// ─── Delete ─────────────────────────────────────────────────────────

class _DeleteAccountSheet extends StatefulWidget {
  final String userId;
  final bool requirePin;
  final ConvexClientWrapper client;

  const _DeleteAccountSheet({required this.userId, required this.requirePin, required this.client});

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  static const _confirmWord = 'DELETE';
  final _typed = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _confirmed => _typed.text.trim().toUpperCase() == _confirmWord;

  Future<void> _submit() async {
    if (widget.requirePin && _pin.text.length != 4) {
      setState(() => _error = 'Enter your 4-digit Account PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await widget.client.mutation('users:requestAccountDeletion', args: {
      'userId': widget.userId,
      if (widget.requirePin) 'currentPin': _pin.text,
    });
    if (!mounted) return;
    final value = res.value;
    if (res.success && value is Map && value['success'] == true) {
      final at = value['deletionScheduledFor'];
      Navigator.of(context).pop(
        at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : DateTime.now().add(const Duration(days: 30)),
      );
      return;
    }
    _pin.clear();
    setState(() {
      _busy = false;
      _error = res.errorMessage ??
          (value is Map ? value['message']?.toString() : null) ??
          'Your request could not be completed. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    const bullet = TextStyle(fontSize: 13, color: AppColors.gray700, height: 1.4);
    return _SheetFrame(
      icon: Icons.warning_amber_rounded,
      iconColor: _danger,
      iconBackground: _dangerSurface,
      title: 'Delete your account?',
      subtitle: 'Your account will be permanently deleted after 30 days.',
      children: [
        const Text('• You will be signed out on every device now.', style: bullet),
        const Text('• Sign in again within 30 days to cancel the deletion.', style: bullet),
        const Text('• Withdraw any wallet balance and settle escrow first.', style: bullet),
        const Text(
          '• Payment, audit and other records the law requires us to keep are retained.',
          style: bullet,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('account-delete-confirm-input'),
          controller: _typed,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Type $_confirmWord to confirm',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (widget.requirePin) ...[
          const SizedBox(height: 14),
          _PinField(key: const Key('account-delete-pin'), controller: _pin, label: 'Account PIN'),
        ],
        const SizedBox(height: 16),
        _SheetError(_error),
        _PrimaryButton(
          key: const Key('account-delete-submit'),
          label: 'Request account deletion',
          color: _danger,
          busy: _busy,
          onPressed: _confirmed ? _submit : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Keep my account', style: TextStyle(color: AppColors.gray600, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
