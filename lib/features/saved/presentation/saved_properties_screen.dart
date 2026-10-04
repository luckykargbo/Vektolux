// lib/features/saved/presentation/saved_properties_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Saved Properties: the listings the signed-in account saved (heart), read from the
// server. Nothing is shown that is not a saved record; a property that is no longer public is
// listed without details so it can be removed. Removing is a server action.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../core/network/convex_client_wrapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/vx_network_image.dart';
import '../../listings/presentation/views/property_detail_screen.dart';
import '../data/saved_listings_api.dart';
import '../domain/saved_listing.dart';

class SavedPropertiesScreen extends StatefulWidget {
  final SavedListingsApi api;

  /// Used to open a saved property exactly as buyers see it (the public, privacy-safe record).
  final ConvexClientWrapper client;

  const SavedPropertiesScreen({super.key, required this.api, required this.client});

  @override
  State<SavedPropertiesScreen> createState() => _SavedPropertiesScreenState();
}

class _SavedPropertiesScreenState extends State<SavedPropertiesScreen> {
  List<SavedListing>? _items;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.savedListings();
      if (!mounted) return;
      setState(() {
        _items = list.where((s) => s.isProperty).toList();
        _error = null;
      });
    } on SavedListingsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  Future<void> _remove(SavedListing item) async {
    if (_busy.contains(item.listingId)) return;
    _busy.add(item.listingId);
    final before = _items;
    setState(() => _items = [for (final s in before ?? const <SavedListing>[]) if (s.listingId != item.listingId) s]);
    try {
      final saved = await widget.api.toggle(listingType: item.listingType, listingId: item.listingId);
      if (saved) {
        // The server says it is saved again (it was not saved when the tap arrived): show the truth.
        await _load();
      }
    } on SavedListingsException catch (e) {
      if (mounted) {
        setState(() => _items = before);
        _snack(e.message);
      }
    } finally {
      _busy.remove(item.listingId);
    }
  }

  Future<void> _open(SavedListing item) async {
    final res = await widget.client.query('realEstate:getPropertyById', args: {'listingId': item.listingId});
    if (!mounted) return;
    final v = res.value;
    // A property the server will not show comes back as null — which the HTTP wrapper hands over as
    // the whole response envelope — so a real record is recognised by its `_id`.
    if (!res.success || v is! Map || v['_id'] == null) {
      _snack('This property is no longer available.');
      return;
    }
    final p = Map<String, dynamic>.from(v);
    final owner = p['owner'] is Map ? Map<String, dynamic>.from(p['owner'] as Map) : const <String, dynamic>{};
    List<String> strings(dynamic x) => x is List ? x.map((e) => e.toString()).where((e) => e.startsWith('http')).toList() : const [];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PropertyDetailScreen(
        id: p['_id']?.toString() ?? item.listingId,
        title: p['title']?.toString() ?? item.title,
        description: p['description']?.toString() ?? '',
        category: p['category']?.toString() ?? item.category ?? 'sale',
        price: (p['price'] as num?)?.toDouble() ?? item.price.toDouble(),
        hourlyRate: (p['hourlyRate'] as num?)?.toDouble(),
        address: p['publicLocation']?.toString() ?? item.location,
        // City-level position only (the same generic values the marketplace passes).
        latitude: 8.484,
        longitude: -13.234,
        imageUrls: strings(p['imageUrls']),
        videoUrls: strings(p['videoUrls']),
        ownerId: p['ownerId']?.toString() ?? item.ownerId,
        ownerName: owner['name']?.toString(),
        bedrooms: (p['bedrooms'] as num?)?.toInt(),
        bathrooms: (p['bathrooms'] as num?)?.toInt(),
        squareMeters: (p['areaSqM'] as num?)?.toDouble(),
        amenities: p['amenities'] is List ? (p['amenities'] as List).map((e) => e.toString()).toList() : const [],
      ),
    ));
    if (mounted) _load(); // the heart on the detail page may have changed
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text('Saved Properties', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: RefreshIndicator(
        color: AppColors.emerald,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (items == null && _error != null)
              _Note(
                icon: Icons.cloud_off_rounded,
                title: _error!,
                action: TextButton(onPressed: _load, child: const Text('Retry')),
              )
            else if (items == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.emerald)))
            else if (items.isEmpty)
              const _Note(
                key: Key('saved-empty'),
                icon: Icons.favorite_border_rounded,
                title: 'No saved properties yet',
                subtitle: 'Tap the heart on a property to save it.',
              )
            else
              for (final s in items) _SavedCard(item: s, onOpen: () => _open(s), onRemove: () => _remove(s)),
          ],
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final SavedListing item;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  const _SavedCard({required this.item, required this.onOpen, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final specs = <(IconData, String)>[
      if ((item.bedrooms ?? 0) > 0) (Icons.bed_outlined, '${item.bedrooms}'),
      if ((item.bathrooms ?? 0) > 0) (Icons.bathtub_outlined, '${item.bathrooms}'),
      if ((item.areaSqM ?? 0) > 0) (Icons.square_foot_rounded, '${item.areaSqM!.round()} m²'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: Key('saved-${item.listingId}'),
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.available ? onOpen : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    height: 84,
                    child: item.available
                        ? VxNetworkImage(imageUrl: item.imageUrl, fallbackIcon: Icons.home_work_outlined, fallbackLabel: 'NO PHOTO YET')
                        : Container(color: AppColors.gray100, child: const Icon(Icons.home_work_outlined, color: AppColors.gray400)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: item.available
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian, height: 1.2)),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 13, color: AppColors.gray400),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(item.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(item.priceLabel,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
                            if (specs.isNotEmpty || item.tag.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (item.tag.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.emeraldSurface, borderRadius: BorderRadius.circular(6)),
                                      child: Text(item.tag, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
                                    ),
                                  for (final (icon, text) in specs)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 13, color: AppColors.gray500),
                                        const SizedBox(width: 3),
                                        Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.gray600)),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ],
                        )
                      : const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('No longer available',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.gray600)),
                        ),
                ),
                IconButton(
                  key: Key('saved-remove-${item.listingId}'),
                  tooltip: 'Remove from saved',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(Icons.favorite_rounded, color: AppColors.error, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _Note({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
        child: Column(
          children: [
            Icon(icon, size: 44, color: AppColors.gray300),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.gray500)),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      );
}
