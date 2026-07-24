import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// Creates a Detail gallery over exactly the shelf items loaded at tap time.
GallerySessionController<Wallpaper> createWallpaperGallerySession({
  required BuildContext context,
  required String identity,
  required List<Wallpaper> wallpapers,
  required int initialIndex,
  GalleryRequestMore? requestMore,
}) {
  return GallerySessionController<Wallpaper>(
    identity: identity,
    items: wallpapers,
    initialIndex: initialIndex,
    prefetchItem: (Wallpaper wallpaper) =>
        _prefetchWallpaper(context, wallpaper),
    requestMore: requestMore,
    itemKey: (Wallpaper wallpaper) => wallpaper.ref.key,
  );
}

/// Stable identity for one query-backed shelf, independent of page number.
String wallpaperListingIdentity(String shelf, SearchQuery query) {
  final Map<String, String> parameters = query.atPage(1).toQueryParameters();
  final List<String> keys = parameters.keys.toList()..sort();
  final String encoded = keys
      .map(
        (String key) =>
            '${Uri.encodeQueryComponent(key)}='
            '${Uri.encodeQueryComponent(parameters[key]!)}',
      )
      .join('&');
  return '$shelf?$encoded';
}

Future<void> _prefetchWallpaper(
  BuildContext context,
  Wallpaper wallpaper,
) async {
  await Future.wait<void>(<Future<void>>[
    precacheImage(
      CachedNetworkImageProvider(
        wallpaper.thumbOriginalUrl,
        cacheManager: thumbnailImageCache,
      ),
      context,
      onError: (Object error, StackTrace? stackTrace) {},
    ),
    precacheImage(
      CachedNetworkImageProvider(
        wallpaper.fullImageUrl,
        cacheManager: fullImageCache,
      ),
      context,
      onError: (Object error, StackTrace? stackTrace) {},
    ),
  ]);
}
