// lib/features/agent/presentation/views/agent_analytics_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent analytics.
// Counts of real server records only (listings by status/type, buyer inquiries, escrow deals,
// viewing passes, followers). Listing views are not tracked by the backend, so no view
// statistics are shown.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';

class AgentAnalyticsScreen extends StatelessWidget {
  const AgentAnalyticsScreen({super.key});

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
          title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: BlocBuilder<AgentWorkspaceCubit, AgentWorkspaceState>(
          builder: (context, s) {
            final listings = s.portfolio;
            final inquiries = s.inquiries.data;
            final deals = s.deals.data;
            return RefreshIndicator(
              color: AppColors.emerald,
              onRefresh: cubit.loadAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AgentTokens.gutter, 14, AgentTokens.gutter, 28),
                children: [
                  _section(
                    'Listings',
                    listings == null
                        ? null
                        : [
                            ('Total', listings.length),
                            ('Active', listings.where((l) => l.liveStatus == ListingLiveStatus.live).length),
                            ('Unpublished', listings.where((l) => !l.isPublished).length),
                            ('Booked / unavailable',
                                listings.where((l) => l.isPublished && l.liveStatus != ListingLiveStatus.live).length),
                            ('For sale', listings.where((l) => l.isForSale).length),
                            ('For rent / short stay', listings.where((l) => l.isForRent).length),
                            ('Representing owners', listings.where((l) => l.isRepresented).length),
                          ],
                    error: s.ownListings.error,
                    onRetry: cubit.loadListings,
                  ),
                  _section(
                    'Buyer inquiries',
                    inquiries == null
                        ? null
                        : [
                            ('Received (latest 30)', inquiries.length),
                            ('Awaiting your reply', inquiries.where((i) => i.isPending).length),
                            ('Accepted', inquiries.where((i) => i.status == 'accepted').length),
                            ('Declined', inquiries.where((i) => i.status == 'declined').length),
                          ],
                    error: s.inquiries.error,
                    onRetry: cubit.loadInquiries,
                  ),
                  _section(
                    'Deals & viewings',
                    deals == null
                        ? null
                        : [
                            ('Active deals', deals.where((d) => d.isActive).length),
                            ('Completed deals', deals.where((d) => d.isCompleted).length),
                            ('Refunded / cancelled', deals.where((d) => d.state == 'REFUNDED' || d.state == 'CANCELLED').length),
                            ('Viewing passes booked', s.viewingRequests),
                          ],
                    error: s.deals.error,
                    onRetry: cubit.loadDeals,
                  ),
                  _section(
                    'Audience',
                    s.profile.data == null
                        ? null
                        : [('Followers', s.profile.data!.followers), ('Following', s.profile.data!.following)],
                    error: s.profile.error,
                    onRetry: cubit.loadProfile,
                  ),
                  const AgentInfoNote(
                    text: 'Listing views are not tracked by Vektolux yet, so view counts are not shown.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _section(String title, List<(String, int)>? rows, {String? error, required VoidCallback onRetry}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AgentTokens.gap),
      child: AgentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            const SizedBox(height: 8),
            if (rows == null)
              error != null ? AgentErrorState(compact: true, message: error, onRetry: onRetry) : const AgentLoading()
            else
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.gray600))),
                      Text(formatCount(value),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
