// lib/features/agent/presentation/views/agent_people_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent followers / following.
// Real follow relationships from social:getFollowersList / social:getFollowingList (the
// server returns the 50 most recent). Tapping a person opens their existing public profile.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../../social/presentation/views/public_profile_screen.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_shell.dart';

enum PeopleKind { followers, following }

class AgentPeopleScreen extends StatefulWidget {
  final PeopleKind kind;
  const AgentPeopleScreen({super.key, required this.kind});

  @override
  State<AgentPeopleScreen> createState() => _AgentPeopleScreenState();
}

class _AgentPeopleScreenState extends State<AgentPeopleScreen> {
  List<PersonSummary>? _people;
  String? _error;

  /// The server returns at most this many rows.
  static const int _serverLimit = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AgentWorkspaceCubit>().api;
    setState(() => _error = null);
    try {
      final list = widget.kind == PeopleKind.followers ? await api.followers() : await api.following();
      if (mounted) setState(() => _people = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.kind == PeopleKind.followers ? 'Followers' : 'Following';
    final people = _people;
    return agentTextScale(
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.obsidian,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: RefreshIndicator(
          color: AppColors.emerald,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (people == null && _error != null)
                Padding(padding: const EdgeInsets.all(AgentTokens.gutter), child: AgentErrorState(message: _error!, onRetry: _load))
              else if (people == null)
                const AgentLoading()
              else if (people.isEmpty)
                AgentEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: widget.kind == PeopleKind.followers ? 'No followers yet' : 'Not following anyone yet',
                  message: widget.kind == PeopleKind.followers
                      ? 'People who follow you on Vektolux will appear here.'
                      : 'Agents and sellers you follow will appear here.',
                )
              else ...[
                for (final p in people) _personTile(context, p),
                if (people.length >= _serverLimit)
                  const Padding(
                    padding: EdgeInsets.all(AgentTokens.gutter),
                    child: Text('Showing the 50 most recent.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.gray500)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _personTile(BuildContext context, PersonSummary p) {
    final client = AgentShellScope.of(context).convexClient;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter, vertical: 2),
      leading: VektoluxAvatar(avatarUrl: p.avatarUrl, name: p.name, radius: 22, borderWidth: 0),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
      subtitle: p.verificationBadge == null
          ? null
          : Text(p.verificationBadge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
      onTap: p.id.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: p.id, convexClient: client))),
    );
  }
}
