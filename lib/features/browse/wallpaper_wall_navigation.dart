/// The two ways off a tile: open it, or act on it where it lies.
///
/// Both need the whole loaded shelf rather than the one wallpaper — the detail
/// screen pages across it, and the quick sheet's *Open* has to land on the same
/// place a tap would — which is why they take a list and an index instead of a
/// [Wallpaper].
///
/// ```dart
/// await openWallpaperDetail(
///   context: context,
///   bridge: bridge,
///   identity: identity,
///   query: query,
///   wallpapers: loaded,
///   selectedIndex: index,
/// );
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/gallery_paging_bridge.dart';
import 'package:tela/features/browse/wallpaper_quick_sheet.dart';
import 'package:tela/features/detail/wallpaper_detail_args.dart';
import 'package:tela/features/detail/wallpaper_gallery_session.dart';

/// Opens the detail screen on [selectedIndex], paging over the whole shelf.
///
/// The session is disposed when detail pops, whatever it returns: the shelf
/// created it, so the shelf ends it.
Future<void> openWallpaperDetail({
  required BuildContext context,
  required GalleryPagingBridge bridge,
  required String identity,
  required SearchQuery query,
  required List<Wallpaper> wallpapers,
  required int selectedIndex,
  TagFolder? listingFolder,
}) async {
  // `late` so the request-more seam can hand the bridge the very session it
  // belongs to; the closure only runs once the viewer nears the loaded end.
  late final GallerySessionController<Wallpaper> session;
  session = createWallpaperGallerySession(
    context: context,
    identity: identity,
    wallpapers: wallpapers,
    initialIndex: selectedIndex,
    requestMore: () => bridge.appendNextPageInto(session),
  );
  try {
    await context.pushNamed<void>(
      TelaRoutes.detailName,
      pathParameters: <String, String>{
        'wallpaperKey': session.selectedItem.ref.key,
      },
      // The grid's own query travels with the session so a tag or colour
      // followed from the detail screen inherits the filters this listing is
      // under, not Browse's global ones (see WallpaperDetailArgs).
      extra: WallpaperDetailArgs(
        session: session,
        originFilters: query,
        originFolder: listingFolder,
      ),
    );
  } finally {
    session.dispose();
  }
}

/// Favorite, download or set the pressed wallpaper without opening it.
///
/// Only the browse wall has the gesture free. The download history's tiles
/// spend their long press on "forget this row", and taking it over would cost a
/// destructive action its confirmation step; Favorites is left alone for now
/// because the same sheet there would offer to favorite what is already
/// favorited.
Future<void> openWallpaperQuickActions({
  required BuildContext context,
  required WidgetRef ref,
  required List<Wallpaper> wallpapers,
  required int index,
  required VoidCallback openDetail,
}) async {
  final Wallpaper wallpaper = wallpapers[index];
  final WallpaperQuickAction? action = await chooseWallpaperQuickAction(
    context,
    wallpaper,
  );
  if (action == null || !context.mounted) return;
  await runWallpaperQuickAction(
    context: context,
    ref: ref,
    wallpaper: wallpaper,
    action: action,
    openDetail: openDetail,
  );
}
