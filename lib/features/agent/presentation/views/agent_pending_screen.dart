// lib/features/agent/presentation/views/agent_pending_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent access states shown by MainNavigationShell:
//   • AgentPendingScreen   — registered as / applied to be an agent, not approved (yet)
//   • AgentAccessCheckView — while the server status is being read
//   • AgentAccessErrorView — the status could not be read (recoverable)
// None of these grant anything: agent tools stay locked until the server reports approval.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/views/login_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';
import '../../../subscriptions/presentation/views/professional_subscription_screen.dart';
import '../../domain/agent_models.dart';
import '../widgets/agent_ui.dart';

void _logout(BuildContext context) {
  context.read<AuthBloc>().add(const LogoutEvent());
  context.read<ConvexClientWrapper>().clearAuth();
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
}

class AgentPendingScreen extends StatefulWidget {
  final UserEntity user;
  final ProfessionalStatus status;
  /// Re-reads the server status; returns an error message, or null on success.
  final Future<String?> Function() onRefresh;
  final VoidCallback onBrowseAsClient;

  const AgentPendingScreen({
    super.key,
    required this.user,
    required this.status,
    required this.onRefresh,
    required this.onBrowseAsClient,
  });

  @override
  State<AgentPendingScreen> createState() => _AgentPendingScreenState();
}

class _AgentPendingScreenState extends State<AgentPendingScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final error = await widget.onRefresh();
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (error != null) agentSnack(context, error, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.status.latestAgentApplication;
    final (icon, color, title, message) = switch (app?.status) {
      'pending' => (
          Icons.hourglass_top_rounded,
          AppColors.amberDark,
          'Your agent application is under review',
          'A Vektolux administrator is reviewing your Real Estate Agent application. You will be notified when it is decided.',
        ),
      'rejected' => (
          Icons.cancel_outlined,
          AppColors.errorDark,
          'Your agent application was not approved',
          'You can update your details and apply again from your account.',
        ),
      _ => (
          Icons.badge_outlined,
          AppColors.amberDark,
          'Your agent account is not approved yet',
          'Submit your Real Estate Agent application from your account. Agent tools unlock after an administrator approves it.',
        ),
    };
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: RefreshIndicator(
            color: AppColors.emerald,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(icon, size: 36, color: color),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title,
                    key: const Key('agent-pending-title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.gray600, height: 1.45)),
                if (app?.reviewNotes != null) ...[
                  const SizedBox(height: 16),
                  AgentInfoNote(
                    icon: Icons.sticky_note_2_outlined,
                    text: 'Reviewer note: ${app!.reviewNotes}',
                    color: AppColors.obsidian,
                  ),
                ],
                const SizedBox(height: 22),
                const AgentCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What happens next', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                      SizedBox(height: 8),
                      _Step(n: 1, text: 'An administrator reviews and approves your Real Estate Agent role.'),
                      _Step(n: 2, text: 'You activate a professional subscription (required to post listings).'),
                      _Step(n: 3, text: 'Your agent dashboard opens: listings, buyer messages, deals and payouts.'),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  key: const Key('agent-pending-refresh'),
                  onPressed: _refreshing ? null : _refresh,
                  icon: _refreshing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check status again'),
                  style: agentPrimaryButtonStyle(),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ProfileScreen(currentUserId: widget.user.id))),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.obsidian,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Open my account'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfessionalSubscriptionScreen())),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.obsidian,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Subscription plans'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  key: const Key('agent-pending-browse'),
                  onPressed: widget.onBrowseAsClient,
                  style: TextButton.styleFrom(foregroundColor: AppColors.emeraldDark),
                  child: const Text('Continue browsing as a client', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => _logout(context),
                  style: TextButton.styleFrom(foregroundColor: AppColors.gray600),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.emeraldSurface,
            child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.gray700, height: 1.35))),
        ],
      ),
    );
  }
}

/// Shown while the server's professional status is read for an account that may be an agent.
class AgentAccessCheckView extends StatelessWidget {
  const AgentAccessCheckView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        key: Key('agent-access-checking'),
        child: AgentLoading(label: 'Opening your workspace…'),
      ),
    );
  }
}

/// The status could not be read: retry, or continue with the standard app (grants nothing).
class AgentAccessErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  const AgentAccessErrorView({super.key, required this.message, required this.onRetry, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                key: const Key('agent-access-error'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.gray400),
                  const SizedBox(height: 14),
                  const Text(
                    'We could not check your professional account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.gray600)),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: onRetry, style: agentPrimaryButtonStyle(), child: const Text('Try again')),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onContinue,
                    style: TextButton.styleFrom(foregroundColor: AppColors.emeraldDark),
                    child: const Text('Continue to Vektolux', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => _logout(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.gray600),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
