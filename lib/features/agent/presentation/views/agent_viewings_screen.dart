// lib/features/agent/presentation/views/agent_viewings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Viewing requests on the agent's listings (bookings:getVendorBookings).
// States are the server's (a free site visit is confirmed by the server when requested).
// Cancelling uses the existing booking rules (bookings:cancelBooking, refunds as the server decides).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';

class AgentViewingsScreen extends StatefulWidget {
  const AgentViewingsScreen({super.key});

  @override
  State<AgentViewingsScreen> createState() => _AgentViewingsScreenState();
}

class _AgentViewingsScreenState extends State<AgentViewingsScreen> {
  ViewingTab _tab = ViewingTab.upcoming;

  @override
  void initState() {
    super.initState();
    context.read<AgentWorkspaceCubit>().loadViewings();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    return agentTextScale(
      Scaffold(
        backgroundColor: AgentTokens.page,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.obsidian,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: const Text('Viewing Requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
          builder: (context, s) {
            final now = DateTime.now();
            final all = s.viewings.data;
            final shown = all?.where((v) => v.tabAt(now) == _tab).toList();
            if (_tab != ViewingTab.upcoming) shown?.sort((a, b) => b.startTime.compareTo(a.startTime));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 6, AgentTokens.gutter, 12),
                  child: Row(
                    children: [
                      for (final t in ViewingTab.values) ...[
                        if (t != ViewingTab.values.first) const SizedBox(width: 8),
                        Expanded(
                          child: AgentSegment(
                            key: Key('viewings-tab-${t.name}'),
                            label: all == null ? t.label : '${t.label} (${all.where((v) => v.tabAt(now) == t).length})',
                            selected: t == _tab,
                            onTap: () => setState(() => _tab = t),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.emerald,
                    onRefresh: cubit.loadViewings,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, AgentTokens.gutter, 24),
                      children: [
                        if (shown == null && s.viewings.error != null)
                          AgentErrorState(message: s.viewings.error!, onRetry: cubit.loadViewings)
                        else if (shown == null)
                          const AgentLoading()
                        else if (shown.isEmpty)
                          AgentEmptyState(
                            icon: Icons.event_available_outlined,
                            title: switch (_tab) {
                              ViewingTab.upcoming => 'No upcoming viewings',
                              ViewingTab.past => 'No past viewings',
                              ViewingTab.cancelled => 'Nothing cancelled',
                            },
                            message: 'Clients book viewings from your listings.',
                          )
                        else
                          for (final v in shown)
                            Padding(padding: const EdgeInsets.only(bottom: AgentTokens.gap), child: _ViewingCard(viewing: v, now: now)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ViewingCard extends StatelessWidget {
  final ViewingRequest viewing;
  final DateTime now;
  const _ViewingCard({required this.viewing, required this.now});

  Future<void> _cancel(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Cancel this booking?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          content: TextField(
            controller: controller,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Reason for the client'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Keep')),
            TextButton(
              onPressed: controller.text.trim().length < 3 ? null : () => Navigator.of(ctx).pop(controller.text.trim()),
              style: TextButton.styleFrom(foregroundColor: AppColors.errorDark),
              child: const Text('Cancel booking'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    final err = await context.read<AgentWorkspaceCubit>().cancelViewing(viewing, reason);
    if (context.mounted) agentSnack(context, err ?? 'Booking cancelled.', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.fromMillisecondsSinceEpoch(viewing.startTime);
    final (bg, fg) = switch (viewing.status) {
      'confirmed' || 'in_progress' => (AppColors.emeraldSurface, AppColors.emeraldDark),
      'completed' => (AppColors.infoLight, AgentTokens.rentBlue),
      'cancelled' => (AppColors.gray100, AppColors.gray600),
      'disputed' => (AppColors.errorLight, AppColors.errorDark),
      _ => (AppColors.amberSurface, AppColors.amberDark),
    };
    final upcoming = viewing.tabAt(now) == ViewingTab.upcoming;
    final phone = viewing.buyerPhone;
    return AgentCard(
      key: Key('viewing-${viewing.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: AppColors.emeraldSurface, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text(DateFormat('d').format(start),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.emeraldDark, height: 1.1)),
                    Text(DateFormat('MMM').format(start).toUpperCase(),
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(viewing.listingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                    const SizedBox(height: 3),
                    _IconLine(
                      icon: viewing.isSiteVisit ? Icons.directions_walk_rounded : Icons.hotel_outlined,
                      text: '${viewing.typeLabel} · ${DateFormat('EEE h:mm a').format(start)}',
                    ),
                    if (viewing.buyerName != null) ...[
                      const SizedBox(height: 2),
                      _IconLine(icon: Icons.person_outline_rounded, text: viewing.buyerName!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AgentPill(label: viewing.statusLabel, background: bg, foreground: fg),
            ],
          ),
          if (upcoming) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (phone != null)
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                    icon: const Icon(Icons.call_outlined, size: 17),
                    label: const Text('Call client'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.emeraldDark),
                  ),
                TextButton(
                  key: Key('viewing-cancel-${viewing.id}'),
                  onPressed: () => _cancel(context),
                  style: TextButton.styleFrom(foregroundColor: AppColors.errorDark),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.gray500),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.gray600)),
          ),
        ],
      );
}
