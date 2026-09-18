// lib/features/real_estate/presentation/widgets/inspection_pass_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Inspection Pass Modal (Anti-Bypass Micro-Escrow System)
// Allows clients to book viewing tours with micro-escrow fee (SLE 50-100),
// unmasking agent guides while keeping landlord contact & plot coords safe.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../views/my_real_estate_escrows_screen.dart';

class InspectionPassModal extends StatefulWidget {
  final PropertyListingEntity listing;

  const InspectionPassModal({
    super.key,
    required this.listing,
  });

  static Future<void> show({
    required BuildContext context,
    required PropertyListingEntity listing,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<AuthBloc>(),
        child: InspectionPassModal(listing: listing),
      ),
    );
  }

  @override
  State<InspectionPassModal> createState() => _InspectionPassModalState();
}

class _InspectionPassModalState extends State<InspectionPassModal> {
  double _selectedTourFee = 50.0;
  DateTime _scheduledDate = DateTime.now().add(const Duration(hours: 4));
  String _selectedProvider = 'ORANGE_MONEY_SL'; // ORANGE_MONEY_SL, AFRICELL_AFRIMONEY_SL, WALLET
  final _phoneController = TextEditingController();
  bool _isSubmitting = false;
  Map<String, dynamic>? _issuedPass;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthBloc>().state.user;
    if (user != null && user.phone.isNotEmpty) {
      _phoneController.text = user.phone;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleBookPass() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to book a viewing pass.')),
      );
      return;
    }

    if (_selectedProvider != 'WALLET' && _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your mobile money phone number.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      final res = await client.mutation(
        'realEstateEscrow:initiateInspectionPass',
        args: {
          'propertyListingId': widget.listing.id,
          'clientId': user.id,
          'tourFee': _selectedTourFee,
          'scheduledTimestamp': _scheduledDate.millisecondsSinceEpoch,
          'paymentRail': _selectedProvider,
          'paymentPhone': _phoneController.text.trim(),
        },
      );

      if (res.success && res.value != null) {
        setState(() {
          _isSubmitting = false;
          _issuedPass = Map<String, dynamic>.from(res.value as Map);
        });
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.errorMessage ?? 'Failed to issue inspection pass'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            if (_issuedPass != null)
              _buildSuccessView()
            else
              _buildBookingForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingForm() {
    final agentNet = _selectedTourFee * 0.85;
    final platformCut = _selectedTourFee * 0.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.emeraldSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.emeraldDark, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Book Anti-Bypass Tour',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    widget.listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.gray500),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Anti-Bypass Explanation Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.security_rounded, color: AppColors.emerald, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Anti-Bypass Protection: Landlord contact & exact plot coordinates remain masked until verified. Your micro-escrow fee covers your field agent tour guide and is held safely in escrow until you arrive and exchange OTP verification.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.emeraldDark.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Micro-escrow fee selection
        const Text(
          'SELECT INSPECTION TIER',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildFeeOption(
                amount: 50.0,
                title: 'Standard Tour',
                desc: 'Standard Field Agent Guide',
                isSelected: _selectedTourFee == 50.0,
                onTap: () => setState(() => _selectedTourFee = 50.0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFeeOption(
                amount: 100.0,
                title: 'Priority Tour',
                desc: 'Expedited & Senior Agent',
                isSelected: _selectedTourFee == 100.0,
                onTap: () => setState(() => _selectedTourFee = 100.0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Fee distribution breakdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Agent Payout (85%): SLE ${agentNet.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray700),
              ),
              Text(
                'Platform Cut (15%): SLE ${platformCut.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.gray500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Schedule Tour Date & Time
        const Text(
          'SCHEDULE TOUR TIME',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickTourDateTime,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 20, color: AppColors.obsidian),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMM d, yyyy • h:mm a').format(_scheduledDate),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.obsidian),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 16, color: AppColors.gray500),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Payment Rail Selection
        const Text(
          'MICRO-ESCROW PAYMENT METHOD',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRailChip('ORANGE_MONEY_SL', 'Orange', Icons.phone_android_rounded),
            const SizedBox(width: 6),
            _buildRailChip('AFRICELL_AFRIMONEY_SL', 'Afrimoney', Icons.sim_card_outlined),
            const SizedBox(width: 6),
            _buildRailChip('QCELL_QMONEY_SL', 'QMoney', Icons.cell_tower_rounded),
            const SizedBox(width: 6),
            _buildRailChip('WALLET', 'Wallet', Icons.account_balance_wallet_outlined),
          ],
        ),

        if (_selectedProvider != 'WALLET') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Mobile Money Number (Sierra Leone)',
              hintText: 'e.g. 076 123456 or 078 654321',
              prefixIcon: const Icon(Icons.call_outlined, color: AppColors.gray500),
              filled: true,
              fillColor: AppColors.gray50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // CTA Button
        VxButton.primary(
          text: _isSubmitting
              ? 'Locking Micro-Escrow...'
              : 'Lock Escrow Pass (SLE ${_selectedTourFee.toStringAsFixed(0)})',
          icon: Icons.lock_outline_rounded,
          onPressed: _isSubmitting ? null : _handleBookPass,
        ),
      ],
    );
  }

  Widget _buildFeeOption({
    required double amount,
    required String title,
    required String desc,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emeraldSurface : AppColors.gray50,
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SLE ${amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 18),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.obsidian),
            ),
            Text(
              desc,
              style: const TextStyle(fontSize: 10, color: AppColors.gray500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRailChip(String id, String label, IconData icon) {
    final isSelected = _selectedProvider == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedProvider = id),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.obsidian : AppColors.gray100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? AppColors.emerald : AppColors.gray600),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.gray700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickTourDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledDate),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Widget _buildSuccessView() {
    final pass = _issuedPass!;
    final otp = pass['otpCode']?.toString() ?? '----';
    final agentName = pass['assignedAgentName']?.toString() ?? 'Vektolux Field Agent';
    final agentPhone = pass['assignedAgentPhone']?.toString() ?? '+232-xx-xxx-xxx';
    final neighborhood = pass['maskedNeighborhood']?.toString() ?? 'Masked Location';
    final qrHash = pass['qrHash']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.emeraldSurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded, color: AppColors.emerald, size: 36),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Anti-Bypass Inspection Pass Issued!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Micro-escrow locked: SLE ${pass['tourFee'] ?? _selectedTourFee}',
            style: const TextStyle(fontSize: 13, color: AppColors.gray600, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 20),

        // OTP Display Badge
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              const Text(
                'YOUR 4-DIGIT VERIFICATION OTP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.emeraldLight,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: otp.split('').map((digit) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 44,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.emerald.withValues(alpha: 0.8), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      digit,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Provide this OTP to your agent upon arrival to verify visit and release 85% tour fee.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Assigned Agent Guide Info Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.emeraldSurface,
                    child: Icon(Icons.person, color: AppColors.emeraldDark, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agentName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                        ),
                        Text(
                          agentPhone,
                          style: const TextStyle(fontSize: 12, color: AppColors.gray600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.emerald),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: 'OTP: $otp | QR Hash: $qrHash'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pass credentials copied to clipboard!')),
                      );
                    },
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.gray500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Area: $neighborhood',
                      style: const TextStyle(fontSize: 12, color: AppColors.gray700, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('My Escrows'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.obsidian,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MyRealEstateEscrowsScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
