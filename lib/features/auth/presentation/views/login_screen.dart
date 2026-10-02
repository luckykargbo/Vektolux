// lib/features/auth/presentation/views/login_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Login Screen
// Fast sign-in via email/password OR zero-cost Google / Apple social auth.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'complete_profile_phone_screen.dart';

// ── Google Sign-In singleton (Vektolux Google Cloud Project) ───────────────
final _googleSignIn = GoogleSignIn(
  clientId: kIsWeb
      ? AuthConstants.googleWebClientId
      : (defaultTargetPlatform == TargetPlatform.iOS ? AuthConstants.googleIosClientId : null),
  serverClientId: kIsWeb ? null : AuthConstants.googleWebClientId,
  scopes: ['email', 'profile'],
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _socialLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Email / Password login ─────────────────────────────────────────

  void _onLogin() {
    if (_formKey.currentState?.validate() != true) return;
    final raw = _identifierController.text.trim();
    final identifier = raw.contains('@') ? raw.toLowerCase() : raw;
    context.read<AuthBloc>().add(LoginSubmittedEvent(
          identifier: identifier,
          password: _passwordController.text,
        ));
  }

  // ── Google Sign-In ─────────────────────────────────────────────────

  Future<void> _onGoogleSignIn() async {
    setState(() => _socialLoading = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() => _socialLoading = false);
        return; // user cancelled
      }
      final auth = await account.authentication;
      final token = auth.idToken ?? auth.accessToken ?? account.id;
      if (!mounted) {
        setState(() => _socialLoading = false);
        return;
      }
      context.read<AuthBloc>().add(SocialAuthEvent(
            provider: 'google',
            token: token,
            email: account.email,
            name: account.displayName,
            avatarUrl: account.photoUrl,
          ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Google sign-in failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  // ── Apple Sign-In ──────────────────────────────────────────────────

  Future<void> _onAppleSignIn() async {
    setState(() => _socialLoading = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null || !mounted) {
        setState(() => _socialLoading = false);
        return;
      }
      final name = [
        credential.givenName,
        credential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

      final email = credential.email ??
          '${credential.userIdentifier ?? 'apple_user'}@privaterelay.appleid.com';

      context.read<AuthBloc>().add(SocialAuthEvent(
            provider: 'apple',
            token: idToken,
            email: email,
            name: name.isNotEmpty ? name : null,
          ));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User closed/cancelled sheet (error 1001) - ignore silently
        return;
      } else if (e.code == AuthorizationErrorCode.unknown) {
        // Error 1000 - capabilities / simulator / unconfigured signing
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Apple Sign-in is initializing. Please verify developer capabilities or sign in with password/Google.',
            ),
            backgroundColor: AppColors.amber,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Apple sign-in failed: ${e.message}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Apple sign-in failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.needsPhoneSetup && state.user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CompleteProfilePhoneScreen(user: state.user!),
            ),
          );
        } else if (state.status == AuthStatus.authenticated && state.user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigationShell()),
          );
        } else if (state.status == AuthStatus.error &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.errorMessage!),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // ── Brand Header ───────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppColors.emerald.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.lock_person_outlined,
                            size: 34,
                            color: AppColors.emerald,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'VEKTOLUX',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                            letterSpacing: 6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'Welcome Back',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to access your services and wallet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // ── Social Auth Buttons ────────────────────────────
                  _SocialAuthButton(
                    onTap: _socialLoading ? null : _onGoogleSignIn,
                    logo: _GoogleLogo(),
                    label: 'Continue with Google',
                    isLoading: _socialLoading,
                  ),

                  // Apple sign-in: required on iOS, hidden on Android & Web
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 12),
                    _SocialAuthButton(
                      onTap: _socialLoading ? null : _onAppleSignIn,
                      logo: const Icon(Icons.apple, size: 22),
                      label: 'Sign in with Apple',
                      isLoading: _socialLoading,
                      darkMode: true,
                    ),
                  ],

                  // ── Divider ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or sign in with password',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                  ),

                  // ── Email or Phone ─────────────────────────────────
                  TextFormField(
                    controller: _identifierController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Email or Phone Number',
                      hintText: 'e.g. lamin@example.com or +23276123456',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your email or phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Password ───────────────────────────────────────
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ── Forgot Password ────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(
                            initialIdentifier:
                                _identifierController.text.trim(),
                          ),
                        ));
                      },
                      child: const Text('Forgot Password?'),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Sign In Button ─────────────────────────────────
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      final isLoading = state.status == AuthStatus.loggingIn;
                      return SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed:
                              (isLoading || _socialLoading) ? null : _onLogin,
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.white,
                                  ),
                                )
                              : const Text('Sign In'),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // ── Switch to Registration ─────────────────────────
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Don\'t have an account? ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen()),
                            );
                          },
                          child: const Text(
                            'Create Account',
                            style: TextStyle(
                              color: AppColors.emerald,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Social Auth Button Widget ────────────────────────────────────────────

class _SocialAuthButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget logo;
  final String label;
  final bool isLoading;
  final bool darkMode;

  const _SocialAuthButton({
    required this.onTap,
    required this.logo,
    required this.label,
    this.isLoading = false,
    this.darkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = darkMode ? const Color(0xFF000000) : Colors.white;
    final textColor = darkMode ? Colors.white : const Color(0xFF1F1F1F);
    final borderColor = darkMode ? Colors.transparent : const Color(0xFFDADCE0);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          side: BorderSide(color: borderColor),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: darkMode ? Colors.white : AppColors.obsidian,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  logo,
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Google Logo ──────────────────────────────────────────────────────────

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = rect.center;
    final r = size.width / 2;

    // Clip to circle
    canvas.save();
    canvas.clipRect(rect);

    final paint = Paint()..style = PaintingStyle.fill;

    // Blue (right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: r), -0.524, 3.665, true, paint);

    // Red (top-left)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: r), 3.665, 1.571, true, paint);

    // Yellow (bottom-left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: r), 2.094, 1.571, true, paint);

    // Green (bottom-right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: r), 0, 2.094, true, paint);

    // White center
    paint.color = Colors.white;
    canvas.drawCircle(center, r * 0.58, paint);

    // Blue "G" bar
    paint.color = const Color(0xFF4285F4);
    final barRect = Rect.fromLTWH(
      center.dx - r * 0.02,
      center.dy - r * 0.22,
      r * 0.88,
      r * 0.44,
    );
    canvas.drawRect(barRect, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter oldDelegate) => false;
}
