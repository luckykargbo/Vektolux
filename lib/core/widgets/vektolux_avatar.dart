// lib/core/widgets/vektolux_avatar.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Universal User Avatar Component
// Displays network profile photo with automatic fallback to dynamic name
// initials (e.g. "MK") on a sleek gradient, or neutral vector silhouette.
// Supports an optional camera edit badge for profile settings.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class VektoluxAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? name;
  final double radius;
  final double borderWidth;
  final Color borderColor;
  final bool showEditBadge;
  final VoidCallback? onEditTap;
  final VoidCallback? onTap;

  const VektoluxAvatar({
    super.key,
    this.avatarUrl,
    this.name,
    this.radius = 24,
    this.borderWidth = 2.0,
    this.borderColor = AppColors.emerald,
    this.showEditBadge = false,
    this.onEditTap,
    this.onTap,
  });

  /// Extracts up to two uppercase letters from the user's name.
  String get initials {
    if (name == null || name!.trim().isEmpty) return '';
    final parts = name!.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '';
    }
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final size = radius * 2;

    Widget avatarContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderWidth > 0 ? Border.all(color: borderColor, width: borderWidth) : null,
        gradient: !hasImage
            ? const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                avatarUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );

    if (showEditBadge) {
      avatarContent = Stack(
        clipBehavior: Clip.none,
        children: [
          avatarContent,
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: onEditTap ?? onTap,
              child: Container(
                padding: EdgeInsets.all(radius > 30 ? 6 : 4),
                decoration: BoxDecoration(
                  color: AppColors.emerald,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emerald.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: radius > 30 ? 14 : 11,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }

    return avatarContent;
  }

  Widget _buildPlaceholder() {
    final displayInitials = initials;
    if (displayInitials.isNotEmpty) {
      return Center(
        child: Text(
          displayInitials,
          style: TextStyle(
            color: AppColors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return Center(
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.1,
        color: const Color(0xFF94A3B8),
      ),
    );
  }
}
