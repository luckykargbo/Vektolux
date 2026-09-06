// lib/features/mobility/presentation/widgets/group_trip_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Group Ride Sharing & Split-Trip ("Travel Together") Sheet
// Enables group booking invitations, co-rider tracking, multi-stop additions,
// and split-fare calculations across Sierra Leone.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';

class GroupCoRider {
  final String name;
  final String phone;
  final String stopLocation;
  final bool isHost;
  final double shareAmount;

  const GroupCoRider({
    required this.name,
    required this.phone,
    required this.stopLocation,
    this.isHost = false,
    required this.shareAmount,
  });
}

class GroupTripSheet extends StatefulWidget {
  final String pickupAddress;
  final String dropoffAddress;
  final double totalFare;
  final String vehicleType;
  final ValueChanged<List<String>>? onStopsUpdated;

  const GroupTripSheet({
    super.key,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.totalFare,
    this.vehicleType = 'Bajaj Kekeh Tricycle',
    this.onStopsUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required String pickupAddress,
    required String dropoffAddress,
    required double totalFare,
    String vehicleType = 'Bajaj Kekeh Tricycle',
    ValueChanged<List<String>>? onStopsUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupTripSheet(
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        totalFare: totalFare,
        vehicleType: vehicleType,
        onStopsUpdated: onStopsUpdated,
      ),
    );
  }

  @override
  State<GroupTripSheet> createState() => _GroupTripSheetState();
}

class _GroupTripSheetState extends State<GroupTripSheet> {
  late final String _groupTripToken;
  late final List<GroupCoRider> _coRiders;
  final _newStopController = TextEditingController();
  bool _isAddingStop = false;

  @override
  void initState() {
    super.initState();
    _groupTripToken = 'VKT-SL-${(1000 + DateTime.now().millisecond * 7).toString().substring(0, 4)}';
    _recalculateShares(initial: true);
  }

  @override
  void dispose() {
    _newStopController.dispose();
    super.dispose();
  }

  void _recalculateShares({bool initial = false}) {
    if (initial) {
      _coRiders = [
        GroupCoRider(
          name: 'You (Organizer)',
          phone: '+232 76 123 456',
          stopLocation: widget.dropoffAddress,
          isHost: true,
          shareAmount: widget.totalFare,
        ),
      ];
      return;
    }

    final perPerson = (widget.totalFare / _coRiders.length).roundToDouble();
    for (int i = 0; i < _coRiders.length; i++) {
      _coRiders[i] = GroupCoRider(
        name: _coRiders[i].name,
        phone: _coRiders[i].phone,
        stopLocation: _coRiders[i].stopLocation,
        isHost: _coRiders[i].isHost,
        shareAmount: perPerson,
      );
    }
  }

  void _addFriendStop() {
    if (_newStopController.text.trim().isEmpty) return;

    setState(() {
      _coRiders.add(
        GroupCoRider(
          name: 'Friend #${_coRiders.length}',
          phone: '+232 78 ...',
          stopLocation: _newStopController.text.trim(),
          isHost: false,
          shareAmount: 0,
        ),
      );
      _recalculateShares();
      _newStopController.clear();
      _isAddingStop = false;
    });

    widget.onStopsUpdated?.call(_coRiders.map((r) => r.stopLocation).toList());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Intermediate stop added! Fare split recalculated.'),
        backgroundColor: AppColors.emerald,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _inviteDeepLink => 'app://vektolux/trip?token=$_groupTripToken';

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag Handle ───────────────────────────────────────────
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Title Header ──────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: AppColors.emeraldDark,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Travel Together / Group Trip',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.obsidian,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Share ride with friends, split fares & add stops',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.gray500),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Trip Invite Code Banner ───────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TRIP INVITE TOKEN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.gray500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _groupTripToken,
                          style: const TextStyle(
                            fontSize: 18,
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.w800,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  VxButton.small(
                    label: 'Copy Link',
                    icon: Icons.copy_rounded,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _inviteDeepLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Trip invite link copied to clipboard!'),
                          backgroundColor: AppColors.emerald,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.share_rounded, color: Color(0xFF25D366), size: 20),
                      tooltip: 'Share via WhatsApp',
                      onPressed: () {
                        final msg = 'Join my Vektolux ride (${widget.vehicleType}) in Freetown!\n'
                            'Token: $_groupTripToken\n'
                            'Invite Link: $_inviteDeepLink';
                        Clipboard.setData(ClipboardData(text: msg));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('WhatsApp invitation copied to clipboard!'),
                            backgroundColor: AppColors.emerald,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Split Fare Breakdown ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Co-Riders & Split Fare',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SLE ${(_coRiders.first.shareAmount).toStringAsFixed(0)} / rider',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Rider List
            ...List.generate(_coRiders.length, (idx) {
              final rider = _coRiders[idx];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: rider.isHost ? AppColors.emerald : AppColors.gray200,
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: rider.isHost ? AppColors.white : AppColors.obsidian,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rider.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                          Text(
                            'Dropoff: ${rider.stopLocation}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'SLE ${rider.shareAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
              );
            }),

            // ── Add Multi-Stop Point ──────────────────────────────────
            if (!_isAddingStop)
              TextButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined, color: AppColors.emerald, size: 18),
                label: const Text(
                  '+ Add Intermediate Pickup Stop for Co-Rider',
                  style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                onPressed: () => setState(() => _isAddingStop = true),
              )
            else
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter Intermediate Stop / Landmark (e.g. Congo Cross)',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newStopController,
                            style: const TextStyle(fontSize: 13, color: AppColors.obsidian),
                            decoration: InputDecoration(
                              hintText: 'e.g. Congo Cross Junction',
                              filled: true,
                              fillColor: AppColors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        VxButton.small(
                          label: 'Add Stop',
                          onPressed: _addFriendStop,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 18),

            // ── Confirm Group Booking Action ──────────────────────────
            VxButton.primary(
              text: 'Confirm Group Ride (${_coRiders.length} Co-Riders)',
              icon: Icons.check_circle_rounded,
              height: 48,
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Group trip active! Live tracking link active for ${_coRiders.length} riders.',
                    ),
                    backgroundColor: AppColors.emerald,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
