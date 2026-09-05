// lib/features/mobility/presentation/widgets/landmark_autocomplete_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Reverse-Geocoding & Landmark Auto-Suggest Sheet
// Provides instant auto-suggest for local Sierra Leone landmarks
// with pin-drag mode activation and zero-block fallback.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/location_manager.dart';

class LandmarkAutocompleteSheet extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<LocationLandmark> onSelectLandmark;
  final VoidCallback onEnablePinDrag;

  const LandmarkAutocompleteSheet({
    super.key,
    this.initialQuery = '',
    required this.onSelectLandmark,
    required this.onEnablePinDrag,
  });

  static Future<void> show(
    BuildContext context, {
    String initialQuery = '',
    required ValueChanged<LocationLandmark> onSelectLandmark,
    required VoidCallback onEnablePinDrag,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: LandmarkAutocompleteSheet(
          initialQuery: initialQuery,
          onSelectLandmark: (landmark) {
            Navigator.of(ctx).pop();
            onSelectLandmark(landmark);
          },
          onEnablePinDrag: () {
            Navigator.of(ctx).pop();
            onEnablePinDrag();
          },
        ),
      ),
    );
  }

  @override
  State<LandmarkAutocompleteSheet> createState() => _LandmarkAutocompleteSheetState();
}

class _LandmarkAutocompleteSheetState extends State<LandmarkAutocompleteSheet> {
  late final TextEditingController _controller;
  final LocationManager _locationManager = LocationManager();
  List<LocationLandmark> _filteredLandmarks = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _filteredLandmarks = _locationManager.searchLandmarks(widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String val) {
    setState(() {
      _filteredLandmarks = _locationManager.searchLandmarks(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Search Field Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: AppColors.emerald, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            onChanged: _onQueryChanged,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.obsidian,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search landmark (e.g. Lumley, Wilberforce)...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: AppColors.gray400,
                                fontWeight: FontWeight.normal,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_controller.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _controller.clear();
                              _onQueryChanged('');
                            },
                            child: const Icon(Icons.close_rounded, color: AppColors.gray400, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quick Action: Set via interactive Pin Drag
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: widget.onEnablePinDrag,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: AppColors.emerald, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pinpoint Exact Spot on Map (Interactive Pin-Drag)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.emeraldDark, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // Landmarks List
          Flexible(
            child: _filteredLandmarks.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_rounded, color: AppColors.gray400, size: 36),
                        SizedBox(height: 8),
                        Text(
                          'No matching Sierra Leone landmarks',
                          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filteredLandmarks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                    itemBuilder: (context, index) {
                      final landmark = _filteredLandmarks[index];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.gray100,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.location_city_rounded,
                              color: AppColors.obsidian,
                              size: 20,
                            ),
                          ),
                        ),
                        title: Text(
                          landmark.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.obsidian,
                          ),
                        ),
                        subtitle: Text(
                          '${landmark.neighborhood} • ${landmark.category}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.gray400,
                        ),
                        onTap: () => widget.onSelectLandmark(landmark),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
