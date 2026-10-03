// lib/features/agent/presentation/widgets/agent_ui.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Agent workspace: shared building blocks.
// Clean white surfaces, Vektolux green for primary actions and selection, dark headings,
// muted secondary text, rounded cards with subtle borders. Built on the app theme colours and
// the shared image / avatar widgets.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../domain/agent_models.dart';

/// Layout tokens for every agent screen.
class AgentTokens {
  AgentTokens._();
  static const double gutter = 16;
  static const double gap = 12;
  static const double sectionGap = 22;
  static const double radius = 16;

  /// Dense dashboard: cap iOS Dynamic Type so cards and one-line labels keep their structure.
  static const double maxTextScale = 1.15;

  static const Color page = Color(0xFFF8FAFC);
  static const Color deepGreen = Color(0xFF047857);
  static const Color rentBlue = Color(0xFF2563EB);
  static const Color stayAmber = Color(0xFFB45309);
}

/// Clamps text scaling for one agent screen.
Widget agentTextScale(Widget child) => Builder(
      builder: (context) => MediaQuery.withClampedTextScaling(maxScaleFactor: AgentTokens.maxTextScale, child: child),
    );

/// White rounded card with a hairline border and a soft shadow.
class AgentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AgentCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AgentTokens.radius);
    final content = Padding(padding: padding, child: child);
    // The card is its own Material, so ink splashes of InkWells / ListTiles inside it are visible.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// "Recent Listings ............ See All →"
class AgentSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AgentSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.emeraldDark,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(44, 36),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_rounded, size: 15),
              ],
            ),
          ),
      ],
    );
  }
}

/// Listing status from the server ("Active", "Unpublished", "Booked" …).
class AgentStatusPill extends StatelessWidget {
  final ListingLiveStatus status;
  const AgentStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      ListingLiveStatus.live => (AppColors.emeraldSurface, AppColors.emeraldDark),
      ListingLiveStatus.unpublished => (AppColors.amberSurface, AppColors.amberDark),
      ListingLiveStatus.booked => (AppColors.infoLight, AgentTokens.rentBlue),
      ListingLiveStatus.unavailable || ListingLiveStatus.maintenance => (AppColors.gray100, AppColors.gray600),
    };
    return AgentPill(label: status.label, background: bg, foreground: fg);
  }
}

class AgentPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const AgentPill({super.key, required this.label, required this.background, required this.foreground, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// "For Sale" / "For Rent" / "Short Stay" tag drawn over a listing photo.
class AgentCategoryTag extends StatelessWidget {
  final AgentListing listing;
  const AgentCategoryTag({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final label = listing.categoryLabel;
    if (label == null) return const SizedBox.shrink();
    final color = switch (listing.category) {
      'long_term_rent' => AgentTokens.rentBlue,
      'hourly_guesthouse' => AgentTokens.stayAmber,
      _ => AppColors.emeraldDark,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Listing photo with the category tag; a branded placeholder when the listing has no photo.
class AgentListingImage extends StatelessWidget {
  final AgentListing listing;
  final double aspectRatio;
  final BorderRadius borderRadius;

  const AgentListingImage({
    super.key,
    required this.listing,
    this.aspectRatio = 1.45,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VxNetworkImage(
            imageUrl: listing.coverImage,
            borderRadius: borderRadius,
            fallbackIcon: Icons.home_work_outlined,
            // Always an honest label (the widget's default fallback text claims "verified").
            fallbackLabel: listing.coverImage == null ? 'NO PHOTO YET' : 'PHOTO UNAVAILABLE',
          ),
          Positioned(left: 8, top: 8, child: AgentCategoryTag(listing: listing)),
        ],
      ),
    );
  }
}

/// Small square photo (inquiry / invitation context); plain placeholder at any size.
class AgentThumb extends StatelessWidget {
  final String? url;
  final double size;
  final IconData icon;

  const AgentThumb({super.key, required this.url, this.size = 48, this.icon = Icons.home_work_outlined});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: AppColors.gray100,
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.45, color: AppColors.gray400),
    );
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: (u == null || !u.startsWith('http'))
          ? placeholder
          : Image.network(u, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
    );
  }
}

/// Bedrooms · bathrooms · area — only the details the listing really has.
class AgentListingSpecs extends StatelessWidget {
  final AgentListing listing;
  const AgentListingSpecs({super.key, required this.listing});

  static bool hasAny(AgentListing l) =>
      (l.bedrooms ?? 0) > 0 || (l.bathrooms ?? 0) > 0 || (l.areaSqM ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final beds = listing.bedrooms;
    final baths = listing.bathrooms;
    final area = listing.areaSqM;
    final specs = <(IconData, String)>[
      if (beds != null && beds > 0) (Icons.bed_outlined, '$beds'),
      if (baths != null && baths > 0) (Icons.bathtub_outlined, '$baths'),
      if (area != null && area > 0) (Icons.square_foot_rounded, '${formatCount(area.round())} m²'),
    ];
    if (specs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final (icon, text) in specs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.gray500),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.gray600, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Location line with a pin (generalised location only).
class AgentLocationLine extends StatelessWidget {
  final String text;
  const AgentLocationLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.location_on_outlined, size: 13, color: AppColors.gray400),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.gray500),
          ),
        ),
      ],
    );
  }
}

class AgentEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AgentEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.emeraldSurface, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.emeraldDark, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.gray500, height: 1.4),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionLabel!),
              style: agentPrimaryButtonStyle(),
            ),
          ],
        ],
      ),
    );
  }
}

class AgentErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool compact;

  const AgentErrorState({super.key, required this.message, required this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: compact ? 4 : 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.errorDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: AppColors.errorDark, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.errorDark, minimumSize: const Size(44, 36)),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Neutral information strip (e.g. "Video highlights are not supported yet").
class AgentInfoNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color background;

  const AgentInfoNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = AppColors.gray600,
    this.background = AppColors.gray100,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.4))),
        ],
      ),
    );
  }
}

class AgentLoading extends StatelessWidget {
  final String? label;
  const AgentLoading({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.emerald),
          ),
          if (label != null) ...[
            const SizedBox(height: 10),
            Text(label!, style: const TextStyle(fontSize: 12.5, color: AppColors.gray500)),
          ],
        ],
      ),
    );
  }
}

/// Grey placeholder blocks shown while the first page of listings loads.
class AgentSkeletonList extends StatelessWidget {
  final int count;
  const AgentSkeletonList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(6)),
        );
    return Column(
      key: const ValueKey('agent-skeleton'),
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AgentTokens.gap),
            child: AgentCard(
              child: Row(
                children: [
                  Container(
                    width: 104,
                    height: 82,
                    decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [bar(140, 12), const SizedBox(height: 8), bar(90, 10), const SizedBox(height: 8), bar(110, 12)],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Small red badge with a count (9+ above nine), or a dot when [count] is null.
class AgentCountBadge extends StatelessWidget {
  final int? count;
  const AgentCountBadge({super.key, this.count});

  @override
  Widget build(BuildContext context) {
    if (count == null) {
      return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        count! > 9 ? '9+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, height: 1),
      ),
    );
  }
}

/// Round outlined icon button used in agent headers (notifications, settings, edit).
class AgentHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;

  const AgentHeaderButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 21, color: AppColors.obsidian),
                if (badgeCount > 0) Positioned(right: 4, top: 3, child: AgentCountBadge(count: badgeCount)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle agentPrimaryButtonStyle() => ElevatedButton.styleFrom(
      backgroundColor: AppColors.emeraldDark,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.gray200,
      disabledForegroundColor: AppColors.gray500,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Confirmation dialog; returns true when confirmed.
Future<bool> agentConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.obsidian)),
      content: Text(message, style: const TextStyle(fontSize: 13.5, color: AppColors.gray600, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: destructive ? AppColors.error : AppColors.emeraldDark,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

void agentSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.errorDark : AppColors.emeraldDark,
    ));
}
