// lib/features/agent/presentation/views/agent_earnings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent "Earnings & Payouts".
// Read-only view of server data — nothing is computed from listing prices:
//   • total earnings      walletCore:getEarningsSummary (completed payouts credited to you)
//   • wallet balance      wallet:getUserBalance (available / in escrow / pending)
//   • deals & settlements realEstateEscrow:getMyRealEstateEscrows (amounts fixed by the server
//                         when the order was priced: expected to you, released, fees, commission)
//   • withdrawals         withdrawals:getMyWithdrawals (destination masked by the server)
// Withdrawing uses the existing withdraw flow unchanged.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../wallet_payments/presentation/widgets/withdraw_sheet.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_navigation.dart';

class AgentEarningsScreen extends StatefulWidget {
  const AgentEarningsScreen({super.key});

  @override
  State<AgentEarningsScreen> createState() => _AgentEarningsScreenState();
}

class _AgentEarningsScreenState extends State<AgentEarningsScreen> {
  WalletBalance? _wallet;
  String? _walletError;
  List<WithdrawalRecord>? _withdrawals;
  String? _withdrawalsError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<AgentWorkspaceCubit>();
    final api = cubit.api;
    await Future.wait([
      cubit.loadEarnings(),
      cubit.loadDeals(),
      () async {
        try {
          final w = await api.walletBalance();
          if (mounted) {
            setState(() {
              _wallet = w;
              _walletError = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _walletError = e.toString());
        }
      }(),
      () async {
        try {
          final list = await api.withdrawals();
          if (mounted) {
            setState(() {
              _withdrawals = list;
              _withdrawalsError = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _withdrawalsError = e.toString());
        }
      }(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return agentTextScale(
      Scaffold(
        backgroundColor: AgentTokens.page,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.obsidian,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: const Text('Earnings & Payouts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
          builder: (context, s) => RefreshIndicator(
            color: AppColors.emerald,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 14, AgentTokens.gutter, 28),
              children: [
                _totalEarnings(s),
                const SizedBox(height: AgentTokens.gap),
                _walletCard(),
                const SizedBox(height: AgentTokens.sectionGap),
                AgentSectionHeader(title: 'Deals & settlements', actionLabel: 'Open', onAction: () => openDeals(context)),
                const SizedBox(height: 6),
                ..._deals(s),
                const SizedBox(height: AgentTokens.sectionGap),
                const AgentSectionHeader(title: 'Withdrawal history'),
                const SizedBox(height: 6),
                ..._withdrawalRows(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalEarnings(AgentWorkspaceState s) {
    final e = s.earnings;
    return AgentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total earnings', style: TextStyle(fontSize: 12.5, color: AppColors.gray500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (e.data != null) ...[
            Text(formatMoney(e.data!.totalEarned, currency: e.data!.currency, forceCents: true),
                key: const Key('agent-earnings-screen-total'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            const SizedBox(height: 2),
            Text(
              '${e.data!.count} completed payout${e.data!.count == 1 ? '' : 's'} credited to your wallet'
              '${e.data!.truncated ? ' (latest 500 counted)' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.gray500),
            ),
          ] else if (e.error != null)
            AgentErrorState(compact: true, message: e.error!, onRetry: context.read<AgentWorkspaceCubit>().loadEarnings)
          else
            const AgentLoading(),
        ],
      ),
    );
  }

  Widget _walletCard() {
    final w = _wallet;
    if (w == null) {
      return AgentCard(
        child: _walletError != null ? AgentErrorState(compact: true, message: _walletError!, onRetry: _load) : const AgentLoading(),
      );
    }
    Widget figure(String label, double v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatMoney(v, currency: w.currency, forceCents: true),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
              ),
            ],
          ),
        );
    return AgentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available payout balance', style: TextStyle(fontSize: 12.5, color: AppColors.gray500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(formatMoney(w.available, currency: w.currency, forceCents: true),
              key: const Key('agent-wallet-available'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
          const SizedBox(height: 12),
          Row(children: [figure('Held in escrow', w.escrow), const SizedBox(width: 12), figure('Pending', w.pending)]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: w.available > 0
                  ? () => WithdrawSheet.show(context, availableBalance: w.available, onCompleted: _load)
                  : null,
              icon: const Icon(Icons.account_balance_outlined, size: 18),
              label: const Text('Withdraw'),
              style: agentPrimaryButtonStyle(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _deals(AgentWorkspaceState s) {
    final deals = s.deals.data;
    if (deals == null) {
      return [
        s.deals.error != null
            ? AgentErrorState(message: s.deals.error!, onRetry: context.read<AgentWorkspaceCubit>().loadDeals)
            : const AgentLoading(),
      ];
    }
    if (deals.isEmpty) {
      return [
        const AgentCard(
          child: AgentEmptyState(
            icon: Icons.handshake_outlined,
            title: 'No deals yet',
            message: 'Escrow deals on your listings and what they pay you will appear here.',
          ),
        ),
      ];
    }
    final sorted = [...deals]..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return [
      for (final d in sorted)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AgentCard(
            onTap: () => openDeals(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(d.propertyTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    ),
                    const SizedBox(width: 8),
                    AgentPill(
                      label: d.stateLabel,
                      background: d.isActive ? AppColors.emeraldSurface : AppColors.gray100,
                      foreground: d.isActive ? AppColors.emeraldDark : AppColors.gray600,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(d.code, style: const TextStyle(fontSize: 11.5, color: AppColors.gray500)),
                const SizedBox(height: 8),
                _kv('Expected to you', formatMoney(d.netBeneficiaryExpected, forceCents: true)),
                _kv('Released to you', formatMoney(d.releasedBeneficiaryAmount, forceCents: true)),
                _kv('Platform fee', formatMoney(d.platformFeeAmount, forceCents: true)),
                if (d.agentCommissionAmount > 0) _kv('Agent commission', formatMoney(d.agentCommissionAmount, forceCents: true)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 12.5, color: AppColors.gray500))),
            Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
          ],
        ),
      );

  List<Widget> _withdrawalRows() {
    final list = _withdrawals;
    if (list == null) {
      return [_withdrawalsError != null ? AgentErrorState(message: _withdrawalsError!, onRetry: _load) : const AgentLoading()];
    }
    if (list.isEmpty) {
      return [
        const AgentCard(
          child: AgentEmptyState(
            icon: Icons.account_balance_outlined,
            title: 'No withdrawals yet',
            message: 'Withdrawals you request will appear here with their status.',
          ),
        ),
      ];
    }
    return [
      AgentCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < list.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == list.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.gray100)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatMoney(list[i].amount, currency: list[i].currency, forceCents: true),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                          Text(
                            [
                              formatDate(list[i].createdAt),
                              if (list[i].provider != null) list[i].provider!,
                              if (list[i].destination.isNotEmpty) list[i].destination,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.gray500),
                          ),
                          if (list[i].failureReason != null)
                            Text(list[i].failureReason!, style: const TextStyle(fontSize: 11.5, color: AppColors.errorDark)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _withdrawalStatus(list[i].status),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _withdrawalStatus(String status) {
    final s = status.toLowerCase();
    final (bg, fg) = switch (s) {
      'completed' || 'succeeded' || 'paid' => (AppColors.emeraldSurface, AppColors.emeraldDark),
      'failed' || 'cancelled' || 'rejected' || 'reversed' => (AppColors.errorLight, AppColors.errorDark),
      _ => (AppColors.amberSurface, AppColors.amberDark),
    };
    final label = status.isEmpty ? 'Unknown' : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}';
    return AgentPill(label: label, background: bg, foreground: fg);
  }
}
