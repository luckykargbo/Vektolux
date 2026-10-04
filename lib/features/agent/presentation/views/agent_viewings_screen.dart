// lib/features/agent/presentation/views/agent_viewings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Viewing requests on the listings the agent manages (bookings:getMyViewingRequests).
// A free site visit is a REQUEST: it starts Pending; only the owner or the owner's authorised
// agent can Accept (→ Confirmed) or Decline it (reason required, → Declined), and the server
// notifies the client. A confirmed visit can be cancelled; a pending one is answered, not
// cancelled. Paid tour passes keep their own flow (the "Paid tours" row below).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../real_estate/presentation/views/inspection_pass_verification_screen.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';

class AgentViewingsScreen extends StatefulWidget {
  const AgentViewingsScreen({super.key});

  @override
  State<AgentViewingsScreen> createState() => _AgentViewingsScreenState();
}

class _AgentViewingsScreenState extends State<AgentViewingsScreen> {
  ViewingTab? _tab;

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
            int count(ViewingTab t) => all?.where((v) => v.tab == t).length ?? 0;
            // Open on Pending when something waits for an answer, else on the first non-empty tab.
            // The choice is made once, when the list first arrives: answering the last pending
            // request must not make the screen jump to another tab.
            if (_tab == null && all != null) {
              _tab = count(ViewingTab.pending) > 0
                  ? ViewingTab.pending
                  : ViewingTab.values.firstWhere((t) => count(t) > 0, orElse: () => ViewingTab.pending);
            }
            final tab = _tab ?? ViewingTab.pending;
            final shown = all?.where((v) => v.tab == tab).toList();
            if (shown != null && tab != ViewingTab.pending) shown.sort((a, b) => b.startTime.compareTo(a.startTime));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
                    child: Row(
                      children: [
                        for (final t in ViewingTab.values) ...[
                          if (t != ViewingTab.values.first) const SizedBox(width: 8),
                          AgentSegment(
                            key: Key('viewings-tab-${t.name}'),
                            label: all == null ? t.label : '${t.label} (${count(t)})',
                            selected: t == tab,
                            onTap: () => setState(() => _tab = t),
                          ),
                        ],
                      ],
                    ),
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
                            title: switch (tab) {
                              ViewingTab.pending => 'No pending requests',
                              ViewingTab.confirmed => 'No confirmed viewings',
                              ViewingTab.declined => 'Nothing declined',
                              ViewingTab.cancelled => 'Nothing cancelled',
                            },
                            message: 'New viewing requests appear here.',
                          )
                        else
                          for (final v in shown)
                            Padding(padding: const EdgeInsets.only(bottom: AgentTokens.gap), child: ViewingRequestCard(viewing: v, now: now)),
                        if (s.viewingPasses > 0) _PaidToursRow(count: s.viewingPasses),
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

/// One viewing request: thumbnail, property, client, date and time, status — then the actions
/// the request's state allows.
class ViewingRequestCard extends StatefulWidget {
  final ViewingRequest viewing;
  final DateTime now;
  const ViewingRequestCard({super.key, required this.viewing, required this.now});

  @override
  State<ViewingRequestCard> createState() => _ViewingRequestCardState();
}

class _ViewingRequestCardState extends State<ViewingRequestCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action, String done) async {
    setState(() => _busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    agentSnack(context, err ?? done, error: err != null);
  }

  Future<void> _accept() {
    final cubit = context.read<AgentWorkspaceCubit>();
    return _run(() => cubit.respondToViewing(widget.viewing, accept: true), 'Viewing accepted. The client has been notified.');
  }

  Future<void> _decline() async {
    final cubit = context.read<AgentWorkspaceCubit>();
    final reason = await showAgentReasonSheet(
      context,
      title: 'Decline this request?',
      subtitle: 'The client sees your reason.',
      hint: 'Reason (at least 3 characters)',
      confirmLabel: 'Decline request',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _run(() => cubit.respondToViewing(widget.viewing, accept: false, reason: reason), 'Request declined. The client has been notified.');
  }

  Future<void> _cancel() async {
    final cubit = context.read<AgentWorkspaceCubit>();
    final reason = await showAgentReasonSheet(
      context,
      title: 'Cancel this viewing?',
      subtitle: 'The client is told why.',
      hint: 'Reason (at least 3 characters)',
      confirmLabel: 'Cancel viewing',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _run(() => cubit.cancelViewing(widget.viewing, reason), 'Viewing cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viewing;
    final start = DateTime.fromMillisecondsSinceEpoch(v.startTime);
    final expired = v.isExpired(widget.now);
    final (bg, fg) = switch (v.tab) {
      ViewingTab.pending => (AppColors.amberSurface, AppColors.amberDark),
      ViewingTab.confirmed => (AppColors.emeraldSurface, AppColors.emeraldDark),
      ViewingTab.declined => (AppColors.errorLight, AppColors.errorDark),
      ViewingTab.cancelled => (AppColors.gray100, AppColors.gray600),
    };
    final phone = v.clientPhone;
    final reasonLine = v.tab == ViewingTab.declined ? v.declineReason : (v.tab == ViewingTab.cancelled ? v.cancelReason : null);
    return AgentCard(
      key: Key('viewing-${v.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgentThumb(url: v.listingImage, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(v.listingTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian, height: 1.2)),
                        ),
                        const SizedBox(width: 6),
                        AgentPill(key: Key('viewing-status-${v.id}'), label: v.statusLabel, background: bg, foreground: fg),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _IconLine(icon: Icons.person_outline_rounded, text: v.clientName),
                    const SizedBox(height: 2),
                    _IconLine(icon: Icons.event_outlined, text: DateFormat('EEE d MMM · h:mm a').format(start)),
                    if (v.publicLocation != null) ...[
                      const SizedBox(height: 2),
                      _IconLine(icon: Icons.location_on_outlined, text: v.publicLocation!),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (v.notes != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.gray50, borderRadius: BorderRadius.circular(10)),
              child: Text(v.notes!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.gray600, height: 1.35)),
            ),
          ],
          if (reasonLine != null) ...[
            const SizedBox(height: 8),
            Text('Reason: $reasonLine', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
          ],
          if (v.isRequested) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('viewing-decline-${v.id}'),
                    onPressed: _busy ? null : _decline,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: AppColors.errorDark,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: Key('viewing-accept-${v.id}'),
                    // The server refuses to accept a time that has passed, so it is not offered.
                    onPressed: _busy || expired ? null : _accept,
                    style: agentPrimaryButtonStyle().copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
            if (expired) ...[
              const SizedBox(height: 6),
              const Text('This time has passed — it can only be declined.', style: TextStyle(fontSize: 11.5, color: AppColors.gray500)),
            ],
          ] else if (v.isConfirmed && !expired) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                if (phone != null)
                  TextButton.icon(
                    key: Key('viewing-call-${v.id}'),
                    onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                    icon: const Icon(Icons.call_outlined, size: 17),
                    label: const Text('Call client'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.emeraldDark, minimumSize: const Size(0, 36)),
                  ),
                TextButton(
                  key: Key('viewing-cancel-${v.id}'),
                  onPressed: _busy ? null : _cancel,
                  style: TextButton.styleFrom(foregroundColor: AppColors.errorDark, minimumSize: const Size(0, 36)),
                  child: const Text('Cancel viewing'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Paid tour passes are a separate, existing flow: the agent verifies the client's code on site.
class _PaidToursRow extends StatelessWidget {
  final int count;
  const _PaidToursRow({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AgentCard(
        key: const Key('viewings-paid-tours'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InspectionPassVerificationScreen())),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.infoLight, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.qr_code_scanner_rounded, color: AgentTokens.rentBlue, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Paid tours', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            ),
            AgentPill(label: '$count', background: AppColors.infoLight, foreground: AgentTokens.rentBlue),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
          ],
        ),
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
