// lib/features/subscriptions/presentation/views/professional_subscription_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// Professional subscription (Real Estate Agent / Hotel & Guest House Owner).
//
// Everything shown here comes from Convex:
//   • status, badge and posting rights  → subscriptions:getMyProfessionalStatus (computed server-side)
//   • plans, prices, discounts          → subscriptions:getPlans (set by admins; nothing hardcoded)
// Paying:
//   • from the wallet  → subscriptions:subscribeWithWallet (PIN + idempotency key)
//   • directly         → payments:initiateMoniMePayment(subscriptionTierCode) — the SERVER quotes
//                        the price and activates only after Monime confirms the payment.
// The app never marks a subscription active by itself.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';

class ProfessionalSubscriptionScreen extends StatefulWidget {
  const ProfessionalSubscriptionScreen({super.key});

  @override
  State<ProfessionalSubscriptionScreen> createState() => _ProfessionalSubscriptionScreenState();
}

class _ProfessionalSubscriptionScreenState extends State<ProfessionalSubscriptionScreen> {
  final _fmt = NumberFormat('#,##0.00');
  final _date = DateFormat('d MMM yyyy');

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _roleTarget {
    switch (_status['role']) {
      case 'real_estate_agent':
        return 'agent';
      case 'hotel_owner':
        return 'hotel_operator';
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = context.read<ConvexClientWrapper>();
    final s = await client.query('subscriptions:getMyProfessionalStatus');
    if (!mounted) return;
    if (!s.success || s.value is! Map) {
      setState(() {
        _loading = false;
        _error = s.errorMessage ?? 'Could not load your status.';
      });
      return;
    }
    _status = Map<String, dynamic>.from(s.value as Map);
    _plans = [];
    final target = _roleTarget;
    if (target != null && _status['roleApproved'] == true) {
      final p = await client.query('subscriptions:getPlans', args: {'roleTarget': target});
      if (p.success && p.value is List) {
        _plans = (p.value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Paid, active subscription — as reported by the server. A grace period is NOT a subscription.
  bool get _isActive => _status['hasActiveSubscription'] == true;

  /// Legacy-agent grace window, decided by the server (display only; the server enforces posting).
  bool get _inGrace => _status['isInGracePeriod'] == true;
  num? get _graceEndsAt => _status['gracePeriodEndsAt'] as num?;
  num? get _graceEndedAt => _status['legacyGraceEndedAt'] as num?;

  String _fmtDate(num ms) => _date.format(DateTime.fromMillisecondsSinceEpoch(ms.toInt()));

  num? get _expiresAt => _roleTarget == 'agent' ? _status['agentExpiresAt'] as num? : _status['hotelExpiresAt'] as num?;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Professional subscription')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
                  if (_error == null) ..._body(),
                ],
              ),
            ),
    );
  }

  List<Widget> _body() {
    final target = _roleTarget;
    if (target == null) {
      return [
        _infoCard(
          Icons.info_outline_rounded,
          'No subscription needed',
          'Subscriptions apply to approved Real Estate Agents and Hotel / Guest House Owners. '
              'Apply for one of these roles from your account; an administrator reviews every application.',
        ),
        ..._applications(),
      ];
    }
    if (_status['roleApproved'] != true) {
      return [
        _infoCard(Icons.hourglass_top_rounded, 'Application under review',
            'You can subscribe once an administrator approves your professional role.'),
        ..._applications(),
      ];
    }
    final expires = _expiresAt;
    final graceEnds = _graceEndsAt;
    final graceEnded = _graceEndedAt;
    return [
      if (_isActive)
        _infoCard(
          Icons.verified_rounded,
          'Subscription active',
          expires != null
              ? 'Verified badge and posting are active until ${_fmtDate(expires)}. '
                  'You can renew within 72 hours of expiry.'
              : 'Your subscription is active.',
          color: AppColors.emeraldDark,
        )
      else if (_inGrace && graceEnds != null)
        _infoCard(
          Icons.schedule_rounded,
          'Legacy-agent grace period',
          'Your legacy-agent grace period ends on ${_fmtDate(graceEnds)}. You can keep publishing until then. '
              'This is not a paid subscription — subscribe before it ends to keep posting.',
          color: AppColors.amberDark,
        )
      else
        _infoCard(
          Icons.error_outline_rounded,
          'No active subscription',
          graceEnded != null
              ? 'Your legacy-agent grace period ended on ${_fmtDate(graceEnded)}. Subscribe to publish listings. '
                  'Your existing listings and history are kept.'
              : 'Subscribe to get your verified badge and post listings. Your existing listings and history are kept.',
          color: AppColors.amberDark,
        ),
      const SizedBox(height: 16),
      if (_plans.isEmpty)
        const Text('No plans are available right now. Please check back later.',
            style: TextStyle(color: AppColors.gray600)),
      ..._plans.map(_planCard),
    ];
  }

  List<Widget> _applications() {
    final apps = (_status['applications'] as List?) ?? const [];
    if (apps.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      const Text('Your applications', style: TextStyle(fontWeight: FontWeight.w800)),
      ...apps.map((a) {
        final m = Map<String, dynamic>.from(a as Map);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(m['targetRole']?.toString() ?? ''),
          subtitle: m['reviewNotes'] != null ? Text(m['reviewNotes'].toString()) : null,
          trailing: Text(m['status']?.toString() ?? ''),
        );
      }),
    ];
  }

  Widget _infoCard(IconData icon, String title, String body, {Color color = AppColors.obsidian}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 13, color: AppColors.gray600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> p) {
    final currency = p['currency']?.toString() ?? 'SLE';
    final price = (p['effectivePrice'] as num?) ?? 0;
    final base = (p['basePrice'] as num?) ?? 0;
    final promo = p['isPromoActive'] == true && price < base;
    final features = ((p['features'] as List?) ?? const []).map((e) => e.toString()).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p['name']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            // Price, old price and period wrap on narrow phones instead of overflowing.
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text('$currency ${_fmt.format(price)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.emeraldDark)),
                if (promo)
                  Text('$currency ${_fmt.format(base)}',
                      style: const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.gray500)),
                Text('/ ${p['intervalDays']} days', style: const TextStyle(color: AppColors.gray600)),
              ],
            ),
            if (features.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...features.map((f) => Text('• $f', style: const TextStyle(fontSize: 13))),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _payWithWallet(p),
                    child: const Text('Pay from wallet'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _payDirect(p),
                    child: const Text('Pay directly'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _payWithWallet(Map<String, dynamic> plan) async {
    final pin = await _ask('Confirm with your PIN', 'Security PIN', obscure: true);
    if (pin == null || pin.length < 4 || !mounted) return;
    final client = context.read<ConvexClientWrapper>();
    final res = await client.mutation('subscriptions:subscribeWithWallet', args: {
      'tierCode': plan['tierCode'],
      'pin': pin,
      'idempotencyKey': const Uuid().v4(),
    });
    if (!mounted) return;
    _snack(res.success ? 'Subscription active.' : (res.errorMessage ?? 'Payment failed.'));
    await _load();
  }

  Future<void> _payDirect(Map<String, dynamic> plan) async {
    final phone = await _ask('Mobile money number', '+232 7X XXX XXX', keyboard: TextInputType.phone);
    if (phone == null || !mounted) return;
    final client = context.read<ConvexClientWrapper>();
    final res = await client.action('payments:initiateMoniMePayment', args: {
      // The server ignores this amount and charges the plan's current price.
      'amount': (plan['effectivePrice'] as num?)?.toDouble() ?? 0,
      'subscriptionTierCode': plan['tierCode'],
      'phoneNumber': phone,
    });
    if (!mounted) return;
    final v = res.value is Map ? Map<String, dynamic>.from(res.value as Map) : <String, dynamic>{};
    if (!res.success || v['success'] == false) {
      _snack(res.errorMessage ?? v['message']?.toString() ?? 'Could not start the payment.');
      return;
    }
    final url = (v['checkoutUrl'] ?? '').toString();
    if (url.startsWith('https://')) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete your payment'),
        content: Text(url.startsWith('https://')
            ? 'Finish the payment on the Monime page. Your subscription activates automatically once Monime confirms it.'
            : (v['message']?.toString() ?? 'Follow the prompt on your phone to pay.')),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await client.action('payments:verifyAndSettleMoniMePayment', args: {'reference': v['reference']});
              await _load();
            },
            child: const Text("I've paid — check now"),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<String?> _ask(String title, String hint, {bool obscure = false, TextInputType? keyboard}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboard ?? (obscure ? TextInputType.number : TextInputType.text),
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
