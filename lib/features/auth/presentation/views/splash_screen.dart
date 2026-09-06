// lib/features/auth/presentation/views/splash_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Splash & Branding Screen
// Animated vector logo, background health checks, and role-based routing.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../mobility/presentation/views/mobility_home_screen.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'register_screen.dart';

/// Custom Vektolux brand vector SVG.
const String _kVektoluxSvg = '''
<svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="emeraldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#34D399" />
      <stop offset="100%" stop-color="#059669" />
    </linearGradient>
  </defs>
  <rect x="6" y="6" width="88" height="88" rx="24" fill="#1E293B" stroke="#334155" stroke-width="2"/>
  <path d="M26 30L50 70L74 30" stroke="url(#emeraldGrad)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M36 30L50 54L64 30" stroke="#10B981" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" opacity="0.6"/>
  <circle cx="50" cy="22" r="4.5" fill="#10B981"/>
</svg>
''';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.1, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _animController.forward();

    // Trigger health checks & session verification
    context.read<AuthBloc>().add(const SplashInitEvent());
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) => prev.status != curr.status,
      listener: (context, state) {
        if (state.status == AuthStatus.authenticated && state.user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MobilityHomeScreen(
                currentUserId: state.user!.id,
              ),
            ),
          );
        } else if (state.status == AuthStatus.unauthenticated) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const RegisterScreen(),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.obsidian,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),

              // ── Center Brand Logo & Typography ──────────────────────
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Vector Logo via flutter_svg
                      Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.emerald.withValues(alpha: 0.35),
                              blurRadius: 36,
                              spreadRadius: 6,
                            ),
                            BoxShadow(
                              color: AppColors.emerald.withValues(alpha: 0.15),
                              blurRadius: 72,
                              spreadRadius: 12,
                            ),
                          ],
                        ),
                        child: SvgPicture.string(
                          _kVektoluxSvg,
                          width: 96,
                          height: 96,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Brand Name
                      const Text(
                        'VEKTOLUX',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Tagline
                      const Text(
                        'Sierra Leone\'s Premier Super App',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.gray400,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // ── Activity Spinner ─────────────────────────────────────
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  return const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.emerald,
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
