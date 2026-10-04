// lib/features/agent/presentation/views/agent_listings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent "My Listings" (Listings tab).
//
// • The agent's own listings (realEstate:getMyPropertyListings) with their real server status.
// • Listings the agent represents for an owner (owner-authorised listing agents): read-only
//   here — the owner keeps control; the agent can view it or stop representing it.
// • Pending owner invitations to represent a listing (accept / decline on the server).
// Only the generalised public location is displayed — never the street address, coordinates
// or a private phone number.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_navigation.dart';

class AgentListingsScreen extends StatefulWidget {
  const AgentListingsScreen({super.key});

  @override
  State<AgentListingsScreen> createState() => _AgentListingsScreenState();
}

class _AgentListingsScreenState extends State<AgentListingsScreen> {
  ListingFilter _filter = ListingFilter.all;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AgentWorkspaceCubit>();
    return agentTextScale(
      Scaffold(
        backgroundColor: AgentTokens.page,
        body: SafeArea(
          bottom: false,
          child: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
            builder: (context, s) {
              final portfolio = s.portfolio;
              final canPost = s.status.postingBlockedReason == null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 12, AgentTokens.gutter, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'My Listings',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const Key('agent-add-new'),
                          onPressed: () => openAddListing(context),
                          icon: Icon(canPost ? Icons.add_circle_outline_rounded : Icons.lock_outline_rounded, size: 18),
                          label: const Text('Add New'),
                          style: agentPrimaryButtonStyle().copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
                            backgroundColor: WidgetStatePropertyAll(canPost ? AppColors.emeraldDark : AppColors.gray300),
                            foregroundColor: WidgetStatePropertyAll(canPost ? Colors.white : AppColors.gray700),
                            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterChips(
                    selected: _filter,
                    counts: {
                      for (final f in ListingFilter.values) f: portfolio == null ? null : countMatching(portfolio, f),
                    },
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.emerald,
                      onRefresh: () => Future.wait([cubit.loadListings(), cubit.loadRepresentations()]),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 8, AgentTokens.gutter, 28),
                        children: [
                          ..._invitations(context, s),
                          if (s.representedListings.error != null && s.representedListings.data == null)
                            AgentErrorState(
                              compact: true,
                              message: 'Listings you represent for owners could not load: ${s.representedListings.error}',
                              onRetry: cubit.loadRepresentations,
                            ),
                          ..._listings(context, s, portfolio, canPost),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _invitations(BuildContext context, AgentWorkspaceState s) {
    final invites = s.invitations.data ?? const <AgentInvitation>[];
    if (invites.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Invitations from owners',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
      ),
      for (final inv in invites)
        Padding(padding: const EdgeInsets.only(bottom: AgentTokens.gap), child: _InvitationCard(invitation: inv)),
      const SizedBox(height: 6),
    ];
  }

  List<Widget> _listings(BuildContext context, AgentWorkspaceState s, List<AgentListing>? portfolio, bool canPost) {
    final cubit = context.read<AgentWorkspaceCubit>();
    if (portfolio == null) {
      if (s.ownListings.error != null) {
        return [AgentErrorState(message: s.ownListings.error!, onRetry: cubit.loadListings)];
      }
      return const [AgentSkeletonList()];
    }
    if (portfolio.isEmpty) {
      final reason = s.status.postingBlockedReason;
      return [
        AgentEmptyState(
          icon: Icons.home_work_outlined,
          title: 'No listings yet',
          message: reason == null ? 'Create your first property listing.' : 'Posting opens with an active subscription.',
          actionLabel: canPost ? 'Add Listing' : null,
          onAction: canPost ? () => openAddListing(context) : null,
        ),
      ];
    }
    final visible = portfolio.where((l) => l.matches(_filter)).toList();
    if (visible.isEmpty) {
      return [
        AgentEmptyState(
          icon: Icons.filter_list_rounded,
          title: 'Nothing here',
          message: 'No listings match "${_filter.label}".',
        ),
      ];
    }
    final inquiries = s.inquiriesByListing;
    return [
      for (final l in visible)
        Padding(
          padding: const EdgeInsets.only(bottom: AgentTokens.gap),
          child: AgentListingRow(listing: l, inquiries: inquiries[l.id] ?? 0),
        ),
    ];
  }
}

class _FilterChips extends StatelessWidget {
  final ListingFilter selected;
  final Map<ListingFilter, int?> counts;
  final ValueChanged<ListingFilter> onSelected;

  const _FilterChips({required this.selected, required this.counts, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AgentTokens.gutter),
      child: Row(
        children: [
          for (final f in ListingFilter.values) ...[
            if (f != ListingFilter.values.first) const SizedBox(width: 8),
            _chip(f),
          ],
        ],
      ),
    );
  }

  Widget _chip(ListingFilter f) {
    final isSelected = f == selected;
    final n = counts[f];
    return Material(
      color: isSelected ? AppColors.emeraldDark : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: isSelected ? AppColors.emeraldDark : AppColors.border)),
      child: InkWell(
        key: Key('agent-filter-${f.name}'),
        customBorder: const StadiumBorder(),
        onTap: () => onSelected(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            n == null ? f.label : '${f.label} ($n)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.gray600,
            ),
          ),
        ),
      ),
    );
  }
}

enum _ListingAction { view, edit, publish, unpublish, delete, stopRepresenting }

/// Horizontal listing card (Listings tab) with the actions menu.
class AgentListingRow extends StatelessWidget {
  final AgentListing listing;
  final int inquiries;
  const AgentListingRow({super.key, required this.listing, this.inquiries = 0});

  @override
  Widget build(BuildContext context) {
    return AgentCard(
      key: Key('agent-listing-${listing.id}'),
      padding: const EdgeInsets.all(10),
      onTap: () => openListingDetail(context, listing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: AgentListingImage(listing: listing, aspectRatio: 112 / 96)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian, height: 1.25),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: PopupMenuButton<_ListingAction>(
                        key: Key('agent-listing-menu-${listing.id}'),
                        tooltip: 'Listing actions',
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert_rounded, color: AppColors.gray500, size: 20),
                        color: Colors.white,
                        onSelected: (a) => _handle(context, a),
                        itemBuilder: (_) => _menu(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                AgentLocationLine(text: listing.publicLocation),
                const SizedBox(height: 6),
                Text(
                  listing.priceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                ),
                const SizedBox(height: 6),
                // Specs and status share a line when there is room and wrap on narrow phones.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (AgentListingSpecs.hasAny(listing)) AgentListingSpecs(listing: listing),
                    AgentStatusPill(status: listing.liveStatus),
                    if (inquiries > 0) AgentInquiryChip(count: inquiries),
                  ],
                ),
                if (listing.isRepresented) ...[
                  const SizedBox(height: 6),
                  const AgentPill(
                    label: 'Representing the owner',
                    background: AppColors.infoLight,
                    foreground: AgentTokens.rentBlue,
                    icon: Icons.handshake_outlined,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<_ListingAction>> _menu() {
    PopupMenuItem<_ListingAction> item(_ListingAction a, IconData icon, String label, {Color? color}) => PopupMenuItem(
          value: a,
          child: Row(
            children: [
              Icon(icon, size: 19, color: color ?? AppColors.obsidian),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: color ?? AppColors.obsidian, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    if (listing.isRepresented) {
      return [
        item(_ListingAction.view, Icons.visibility_outlined, 'View listing'),
        item(_ListingAction.stopRepresenting, Icons.link_off_rounded, 'Stop representing', color: AppColors.errorDark),
      ];
    }
    return [
      item(_ListingAction.view, Icons.visibility_outlined, 'View listing'),
      item(_ListingAction.edit, Icons.edit_outlined, 'Edit details'),
      if (listing.isPublished)
        item(_ListingAction.unpublish, Icons.visibility_off_outlined, 'Unpublish')
      else
        item(_ListingAction.publish, Icons.publish_rounded, 'Publish'),
      item(_ListingAction.delete, Icons.delete_outline_rounded, 'Delete', color: AppColors.errorDark),
    ];
  }

  Future<void> _handle(BuildContext context, _ListingAction action) async {
    final cubit = context.read<AgentWorkspaceCubit>();
    switch (action) {
      case _ListingAction.view:
        openListingDetail(context, listing);
        return;
      case _ListingAction.edit:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (_) => BlocProvider.value(value: cubit, child: _EditListingSheet(listing: listing)),
        );
        return;
      case _ListingAction.publish:
        if (!await agentConfirm(context,
            title: 'Publish listing?',
            message: 'It will be visible on the Vektolux marketplace. Vektolux checks your posting permission first.',
            confirmLabel: 'Publish')) {
          return;
        }
        final err = await cubit.setPublished(listing, true);
        if (context.mounted) agentSnack(context, err ?? 'Listing published.', error: err != null);
        return;
      case _ListingAction.unpublish:
        if (!await agentConfirm(context,
            title: 'Unpublish listing?',
            message: 'Buyers will no longer see it. You can publish it again later.',
            confirmLabel: 'Unpublish')) {
          return;
        }
        final err = await cubit.setPublished(listing, false);
        if (context.mounted) agentSnack(context, err ?? 'Listing unpublished.', error: err != null);
        return;
      case _ListingAction.delete:
        if (!await agentConfirm(context,
            title: 'Delete listing?',
            message: '"${listing.title}" will be permanently removed from Vektolux. This cannot be undone.',
            confirmLabel: 'Delete',
            destructive: true)) {
          return;
        }
        final err = await cubit.deleteListing(listing);
        if (context.mounted) agentSnack(context, err ?? 'Listing deleted.', error: err != null);
        return;
      case _ListingAction.stopRepresenting:
        final reason = await _askReason(context);
        if (reason == null) return;
        final err = await cubit.stopRepresenting(listing, reason);
        if (context.mounted) {
          agentSnack(context, err ?? 'You no longer represent this listing. The owner has been notified.', error: err != null);
        }
        return;
    }
  }

  Future<String?> _askReason(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Stop representing this listing?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The owner will be notified. Tell them why.',
                  style: TextStyle(fontSize: 13, color: AppColors.gray600)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLength: 300,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Reason (at least 3 characters)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().length < 3 ? null : () => Navigator.of(ctx).pop(controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, elevation: 0),
              child: const Text('Stop representing'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }
}

class _InvitationCard extends StatefulWidget {
  final AgentInvitation invitation;
  const _InvitationCard({required this.invitation});

  @override
  State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    final err = await context.read<AgentWorkspaceCubit>().respondToInvitation(widget.invitation, accept: accept);
    if (!mounted) return;
    setState(() => _busy = false);
    agentSnack(
      context,
      err ?? (accept ? 'You now represent this listing.' : 'Invitation declined.'),
      error: err != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.invitation.listing;
    return AgentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AgentThumb(url: l?.coverImage, size: 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Owner invitation',
                        style: TextStyle(fontSize: 11.5, color: AgentTokens.rentBlue, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      l?.title ?? 'A property listing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                    ),
                    if (l != null) ...[
                      const SizedBox(height: 2),
                      Text('${l.priceLabel} · ${l.publicLocation}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gray700,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _respond(true),
                  style: agentPrimaryButtonStyle(),
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edits the fields the existing update mutation supports (title, description, price, rooms).
class _EditListingSheet extends StatefulWidget {
  final AgentListing listing;
  const _EditListingSheet({required this.listing});

  @override
  State<_EditListingSheet> createState() => _EditListingSheetState();
}

class _EditListingSheetState extends State<_EditListingSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.listing.title);
  late final TextEditingController _description = TextEditingController(text: widget.listing.description);
  late final TextEditingController _price =
      TextEditingController(text: widget.listing.price > 0 ? widget.listing.price.toStringAsFixed(0) : '');
  late final TextEditingController _beds = TextEditingController(text: widget.listing.bedrooms?.toString() ?? '');
  late final TextEditingController _baths = TextEditingController(text: widget.listing.bathrooms?.toString() ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _beds, _baths]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final price = double.tryParse(_price.text.trim());
    if (title.isEmpty || price == null || price <= 0) {
      setState(() => _error = title.isEmpty ? 'Enter a title.' : 'Enter a valid price.');
      return;
    }
    final beds = _beds.text.trim().isEmpty ? null : int.tryParse(_beds.text.trim());
    final baths = _baths.text.trim().isEmpty ? null : int.tryParse(_baths.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await context.read<AgentWorkspaceCubit>().updateListingDetails(
          widget.listing,
          title: title,
          description: _description.text.trim(),
          price: price,
          bedrooms: beds,
          bathrooms: baths,
        );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop();
    agentSnack(context, 'Listing updated.');
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Edit listing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            const SizedBox(height: 14),
            TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: InputDecoration(labelText: 'Price (${widget.listing.currency})'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _beds,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Bedrooms'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _baths,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Bathrooms'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.errorDark, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: agentPrimaryButtonStyle(),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
