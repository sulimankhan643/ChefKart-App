import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cached image widget for chef profile pictures
/// Provides smooth scrolling with image caching
class CachedChefImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? placeholderText;
  final bool isCircular;

  const CachedChefImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderText,
    this.isCircular = false,
  });

  /// Safely convert double to int, handling infinity and NaN
  int? _getSafeIntValue(double? value) {
    if (value == null || value.isInfinite || value.isNaN) {
      return null;
    }
    return (value * 2).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(context);
    }

    // Use the image URL directly - CachedNetworkImage will cache based on URL
    final effectiveUrl = imageUrl!;

    Widget imageWidget = CachedNetworkImage(
      imageUrl: effectiveUrl,
      cacheKey: effectiveUrl, // Cache key based on full URL (includes timestamp from Supabase)
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => _buildLoadingPlaceholder(context),
      errorWidget: (context, url, error) {
        debugPrint('CachedChefImage error loading: $url - $error');
        return _buildPlaceholder(context);
      },
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 300),
      memCacheWidth: _getSafeIntValue(width),
      memCacheHeight: _getSafeIntValue(height),
      useOldImageOnUrlChange: false, // Show new image immediately when URL changes
    );

    if (isCircular) {
      return ClipOval(child: imageWidget);
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildLoadingPlaceholder(BuildContext context) {
    Widget placeholder = Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).primaryColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );

    if (isCircular) {
      return ClipOval(child: placeholder);
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: placeholder,
      );
    }

    return placeholder;
  }

  Widget _buildPlaceholder(BuildContext context) {
    Widget placeholder = Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: placeholderText != null && placeholderText!.isNotEmpty
            ? Text(
                placeholderText![0].toUpperCase(),
                style: TextStyle(
                  fontSize: height != null ? height! * 0.4 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              )
            : Icon(
                Icons.person,
                size: height != null ? height! * 0.5 : 32,
                color: Colors.grey[400],
              ),
      ),
    );

    if (isCircular) {
      return ClipOval(child: placeholder);
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: placeholder,
      );
    }

    return placeholder;
  }
}

/// Cached image specifically for chef avatars in lists
class CachedChefAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double radius;
  final bool showOnlineStatus;
  final bool isOnline;
  final bool showVerifiedBadge;
  final bool isVerified;

  const CachedChefAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.radius = 30,
    this.showOnlineStatus = false,
    this.isOnline = false,
    this.showVerifiedBadge = false,
    this.isVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CachedChefImage(
          imageUrl: imageUrl,
          width: radius * 2,
          height: radius * 2,
          isCircular: true,
          placeholderText: name,
        ),

        // Online status indicator
        if (showOnlineStatus)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: radius * 0.4,
              height: radius * 0.4,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),

        // Verified badge
        if (showVerifiedBadge && isVerified)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFF2B3A67),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                color: Colors.white,
                size: radius * 0.3,
              ),
            ),
          ),
      ],
    );
  }
}

