// lib/features/agent/presentation/views/agent_navigation.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent workspace: shared destinations.
// Opens the EXISTING app screens where they already exist (listing detail, escrow deals,
// subscription, account settings, bookings) instead of duplicating them.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/views/login_screen.dart';
import '../../../bookings/presentation/views/my_bookings_screen.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';
import '../../../real_estate/presentation/views/my_real_estate_escrows_screen.dart';
import '../../../subscriptions/presentation/views/professional_subscription_screen.dart';
import '../../domain/agent_models.dart';
import '../bloc/agent_workspace_cubit.dart';
import '../widgets/agent_ui.dart';
import 'agent_add_listing_screen.dart';
import 'agent_shell.dart';

/// Add Listing — only offered when the server says the agent may post right now. The server
/// checks again on submission (role approval + active subscription).
Future<void> openAddListing(BuildContext context) async {
  final cubit = context.read<AgentWorkspaceCubit>();
  final reason = cubit.state.status.postingBlockedReason;
  if (reason != null) {
    await showPostingBlockedSheet(context, reason);
    return;
  }
  final created = await pushAgentPage<bool>(context, const AgentAddListingScreen());
  if (created == true) {
    cubit.loadListings();
  }
}

Future<void> showPostingBlockedSheet(BuildContext context, String reason) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_clock_outlined, color: AppColors.amberDark),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Posting is not available',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(reason, style: const TextStyle(fontSize: 13.5, color: AppColors.gray600, height: 1.4)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: agentPrimaryButtonStyle(),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openSubscription(context);
                },
                child: const Text('View subscription plans'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens the listing exactly as buyers see it (the marketplace's detail screen), with the public
/// data only: generalised location, never the street address, coordinates or a private phone.
void openListingDetail(BuildContext context, AgentListing listing) {
  final user = AgentShellScope.of(context).user;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PropertyDetailScreen(
      id: listing.id,
      title: listing.title,
      description: listing.description,
      category: listing.category,
      price: listing.price,
      hourlyRate: listing.hourlyRate,
      address: listing.publicLocation,
      // Same generic city-level values the marketplace passes: never the property's GPS position.
      latitude: 8.484,
      longitude: -13.234,
      imageUrls: listing.imageUrls,
      ownerId: listing.ownerId.isNotEmpty ? listing.ownerId : user.id,
      bedrooms: listing.bedrooms,
      bathrooms: listing.bathrooms,
      squareMeters: listing.areaSqM,
      // Only what the listing really has (the screen's defaults would invent amenities).
      amenities: listing.amenities,
      isFurnished: listing.amenities.contains('Furnished'),
    ),
  ));
}

void openDeals(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRealEstateEscrowsScreen()));
}

void openBookings(BuildContext context) {
  final scope = AgentShellScope.of(context);
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MyBookingsScreen(convexClient: scope.convexClient, currentUser: scope.user),
  ));
}

Future<void> openSubscription(BuildContext context) async {
  final cubit = context.read<AgentWorkspaceCubit>();
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfessionalSubscriptionScreen()));
  // A purchase or renewal changes what the server allows: re-read it.
  cubit.refreshStatus();
}

/// The existing Account screen: profile details, photo, PIN, payment methods, privacy, account
/// deletion — all through the existing account functions.
Future<void> openAccountSettings(BuildContext context) async {
  final user = AgentShellScope.of(context).user;
  final cubit = context.read<AgentWorkspaceCubit>();
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(currentUserId: user.id)));
  cubit.loadProfile();
}

/// Vektolux customer support (the same contact the Account screen offers).
Future<void> showAgentSupportSheet(BuildContext context) {
  const supportPhone = '+23273623761';
  const formattedPhone = '+232 73 623 761';
  final whatsappUri = Uri.parse(
    'https://wa.me/23273623761?text=${Uri.encodeComponent("Hello Vektolux Customer Support, I am a Real Estate Agent and I need help with my account.")}',
  );
  final callUri = Uri.parse('tel:$supportPhone');

  Future<void> launch(BuildContext ctx, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && ctx.mounted) agentSnack(ctx, 'Could not open $formattedPhone on this device.', error: true);
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vektolux Support',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
            const SizedBox(height: 4),
            const Text('Help with listings, subscriptions, payouts or your account.',
                style: TextStyle(fontSize: 13, color: AppColors.gray500)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.emeraldSurface,
                child: Icon(Icons.chat_rounded, color: AppColors.emeraldDark),
              ),
              title: const Text('Chat on WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
              subtitle: const Text(formattedPhone),
              onTap: () => launch(ctx, whatsappUri),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.emeraldSurface,
                child: Icon(Icons.call_rounded, color: AppColors.emeraldDark),
              ),
              title: const Text('Call support', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
              subtitle: const Text(formattedPhone),
              onTap: () => launch(ctx, callUri),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> confirmAgentLogout(BuildContext context) async {
  final ok = await agentConfirm(
    context,
    title: 'Log out?',
    message: 'You will need to sign in again to use your agent workspace.',
    confirmLabel: 'Log Out',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final scope = AgentShellScope.of(context);
  context.read<AuthBloc>().add(const LogoutEvent());
  scope.convexClient.clearAuth();
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}
