// lib/core/widgets/sl_location_picker.dart
// ═══════════════════════════════════════════════════════════════════════
// Sierra Leone location picker: District (grouped by region) → Town.
//
// The list comes from the backend (`locations:getSierraLeoneLocations`) so it is maintained in one
// place. Only these broad names are ever shown publicly ("Inside <Town>, Sierra Leone"); a user's
// private street address is collected separately and never published.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../network/convex_client_wrapper.dart';

class SlDistrict {
  final String region;
  final String district;
  final List<String> towns;
  const SlDistrict(this.region, this.district, this.towns);
}

class SierraLeoneLocationPicker extends StatefulWidget {
  final String? initialDistrict;
  final String? initialTown;
  final bool requireDistrict;
  final void Function(String? district, String? town) onChanged;

  const SierraLeoneLocationPicker({
    super.key,
    required this.onChanged,
    this.initialDistrict,
    this.initialTown,
    this.requireDistrict = false,
  });

  @override
  State<SierraLeoneLocationPicker> createState() => _SierraLeoneLocationPickerState();
}

class _SierraLeoneLocationPickerState extends State<SierraLeoneLocationPicker> {
  static List<SlDistrict>? _cache; // reference data: safe to cache for the app session

  List<SlDistrict> _districts = const [];
  bool _loading = true;
  String? _error;
  String? _district;
  String? _town;

  @override
  void initState() {
    super.initState();
    _district = widget.initialDistrict;
    _town = widget.initialTown;
    _load();
  }

  Future<void> _load() async {
    if (_cache != null) {
      _apply(_cache!);
      return;
    }
    try {
      final res = await context.read<ConvexClientWrapper>().query('locations:getSierraLeoneLocations');
      if (!mounted) return;
      if (res.success && res.value is List) {
        final list = (res.value as List)
            .whereType<Map>()
            .map((m) => SlDistrict(
                  m['region']?.toString() ?? '',
                  m['district']?.toString() ?? '',
                  ((m['towns'] as List?) ?? const []).map((e) => e.toString()).toList(),
                ))
            .where((d) => d.district.isNotEmpty)
            .toList();
        _cache = list;
        _apply(list);
      } else {
        setState(() {
          _loading = false;
          _error = 'Could not load locations. Check your connection.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load locations. Check your connection.';
        });
      }
    }
  }

  void _apply(List<SlDistrict> list) {
    setState(() {
      _districts = list;
      _loading = false;
      _error = null;
      if (_district != null && !list.any((d) => d.district == _district)) _district = null;
      final towns = _townsFor(_district);
      if (_town != null && !towns.contains(_town)) _town = null;
    });
  }

  List<String> _townsFor(String? district) =>
      _districts.firstWhere((d) => d.district == district, orElse: () => const SlDistrict('', '', [])).towns;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          TextButton(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('Retry'),
          ),
        ],
      );
    }

    final towns = _townsFor(_district);
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _district,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: widget.requireDistrict ? 'District (required)' : 'District',
            prefixIcon: const Icon(Icons.map_outlined),
          ),
          items: _districts
              .map((d) => DropdownMenuItem(
                    value: d.district,
                    child: Text('${d.district} — ${d.region}', overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          validator: widget.requireDistrict ? (v) => v == null ? 'Please select a district' : null : null,
          onChanged: (v) {
            setState(() {
              _district = v;
              _town = null;
            });
            widget.onChanged(_district, null);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(_district), // reset when the district changes
          initialValue: _town,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Town / City (optional)',
            prefixIcon: Icon(Icons.place_outlined),
          ),
          items: towns.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: towns.isEmpty
              ? null
              : (v) {
                  setState(() => _town = v);
                  widget.onChanged(_district, _town);
                },
        ),
      ],
    );
  }
}
