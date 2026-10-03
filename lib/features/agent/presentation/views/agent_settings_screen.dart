// lib/features/agent/presentation/views/agent_settings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent settings.
// Links to the EXISTING account and subscription screens (account details are edited only
// through the existing account functions; approval and permissions are not editable).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_navigation.dart';
import 'agent_shell.dart';

class AgentSettingsScreen extends StatelessWidget {
  const AgentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AgentShellScope.of(context);
    final status = context.watch<AgentWorkspaceCubit>().state.status;
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap, {Key? key}) => ListTile(
          key: key,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: CircleAvatar(
            backgroundColor: AppColors.emeraldSurface,
            child: Icon(icon, color: AppColors.emeraldDark, size: 21),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
          onTap: onTap,
        );
    return agentTextScale(
      Scaffold(
        backgroundColor: AgentTokens.page,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.obsidian,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 14, AgentTokens.gutter, 28),
          children: [
            AgentCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  tile(Icons.manage_accounts_outlined, 'Account & profile', 'Name, photo, contact details, PIN and security',
                      () => openAccountSettings(context)),
                  const Divider(height: 1, indent: 70),
                  tile(
                    Icons.workspace_premium_outlined,
                    'Professional subscription',
                    status.hasActiveSubscription
                        ? 'Active${status.agentExpiresAt != null ? ' until ${formatDate(status.agentExpiresAt!)}' : ''}'
                        : 'Not active — required to post listings',
                    () => openSubscription(context),
                  ),
                  const Divider(height: 1, indent: 70),
                  tile(Icons.storefront_outlined, 'Browse as a client', 'Open the standard Vektolux marketplace view', () {
                    Navigator.of(context).popUntil((r) => r == scope.shellRoute || r.isFirst);
                    scope.openClientView();
                  }, key: const Key('agent-settings-client-view')),
                  const Divider(height: 1, indent: 70),
                  tile(Icons.support_agent_rounded, 'Support', 'WhatsApp or call Vektolux support', () => showAgentSupportSheet(context)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const AgentInfoNote(
              text: 'Your agent approval and verified badge are managed by Vektolux and cannot be changed here.',
            ),
          ],
        ),
      ),
    );
  }
}
