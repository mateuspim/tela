import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/tela_shell.dart';
import 'package:tela/core/ui/gallery_route_transitions.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/browse/linked_listing_args.dart';
import 'package:tela/features/browse/linked_listing_screen.dart';
import 'package:tela/features/detail/wallpaper_detail_args.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';
import 'package:tela/features/downloads/download_history_screen.dart';
import 'package:tela/features/downloads/download_immersive_session.dart';
import 'package:tela/features/library/library_screen.dart';
import 'package:tela/features/private_library/private_immersive_session.dart';
import 'package:tela/features/private_library/private_library_screen.dart';
import 'package:tela/features/settings/blocked_tags_screen.dart';
import 'package:tela/features/settings/settings_screen.dart';

/// The app's routes.
///
/// Browse, detail, settings, and favorites are live. Keeping the router apart
/// from the app widget means adding a screen touches this file only.
abstract final class TelaRouter {
  /// Builds the router.
  static GoRouter create() {
    return GoRouter(
      initialLocation: TelaRoutes.browsePath,
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, _, StatefulNavigationShell navigationShell) =>
              TelaShell(navigationShell: navigationShell),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: TelaRoutes.browsePath,
                  name: TelaRoutes.browseName,
                  builder: (_, _) => const BrowseScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: TelaRoutes.libraryPath,
                  name: TelaRoutes.libraryName,
                  builder: (_, _) => const LibraryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: TelaRoutes.settingsPath,
                  name: TelaRoutes.settingsName,
                  builder: (_, _) => const SettingsScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: TelaRoutes.detailPath,
          name: TelaRoutes.detailName,
          redirect: (_, GoRouterState state) =>
              state.extra is Wallpaper ||
                  state.extra is GallerySessionController<Wallpaper> ||
                  state.extra is WallpaperDetailArgs
              ? null
              : TelaRoutes.browsePath,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final Object extra = state.extra!;
            final WallpaperDetailArgs? args = extra is WallpaperDetailArgs
                ? extra
                : null;
            return fadeGalleryPage<void>(
              context: context,
              child: WallpaperDetailScreen(
                wallpaper: extra is Wallpaper ? extra : null,
                gallerySession:
                    args?.session ??
                    (extra is GallerySessionController<Wallpaper>
                        ? extra
                        : null),
                originFilters: args?.originFilters,
                originFolder: args?.originFolder,
              ),
            );
          },
        ),
        GoRoute(
          path: TelaRoutes.linkedListingPath,
          name: TelaRoutes.linkedListingName,
          redirect: (_, GoRouterState state) =>
              state.extra is WallpaperLink || state.extra is LinkedListingArgs
              ? null
              : TelaRoutes.browsePath,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final Object extra = state.extra!;
            final LinkedListingArgs? args = extra is LinkedListingArgs
                ? extra
                : null;
            return fadeGalleryPage<void>(
              context: context,
              child: LinkedListingScreen(
                link: args?.link ?? extra as WallpaperLink,
                seed: args?.seed,
              ),
            );
          },
        ),
        GoRoute(
          path: TelaRoutes.privateLibraryPath,
          name: TelaRoutes.privateLibraryName,
          builder: (_, _) => const PrivateLibraryScreen(),
        ),
        GoRoute(
          path: TelaRoutes.privateViewerPath,
          name: TelaRoutes.privateViewerName,
          redirect: (_, GoRouterState state) =>
              state.extra is GallerySessionController<PrivateImage>
              ? null
              : TelaRoutes.privateLibraryPath,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              fadeGalleryPage<void>(
                context: context,
                child: PrivateImmersiveSession(
                  session:
                      state.extra! as GallerySessionController<PrivateImage>,
                ),
              ),
        ),
        GoRoute(
          path: TelaRoutes.downloadHistoryPath,
          name: TelaRoutes.downloadHistoryName,
          // `?tag=` opens the shelf already narrowed, which is what a tag row
          // in the Library hub promises. Read through `TagFolder.isLegal`
          // rather than trusted: this arrives as a URL, and a name that could
          // not be a folder cannot be one anything is filed under either.
          builder: (_, GoRouterState state) => DownloadHistoryScreen(
            tag: _tagFrom(state.uri.queryParameters['tag']),
          ),
        ),
        GoRoute(
          path: TelaRoutes.blockedTagsPath,
          name: TelaRoutes.blockedTagsName,
          builder: (_, _) => const BlockedTagsScreen(),
        ),
        GoRoute(
          path: TelaRoutes.downloadViewerPath,
          name: TelaRoutes.downloadViewerName,
          redirect: (_, GoRouterState state) =>
              state.extra is GallerySessionController<DownloadRecord>
              ? null
              : TelaRoutes.downloadHistoryPath,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              fadeGalleryPage<void>(
                context: context,
                child: DownloadImmersiveSession(
                  session:
                      state.extra! as GallerySessionController<DownloadRecord>,
                ),
              ),
        ),
      ],
    );
  }
}

/// A tag named in a URL, or null when it is absent or not a legal folder name.
///
/// Read rather than trusted: this arrives as a query parameter, and a name that
/// could not be a folder is not one anything is filed under either. Null simply
/// opens the shelf unfiltered, which is where it opens anyway.
TagFolder? _tagFrom(String? raw) {
  if (raw == null || !TagFolder.isLegal(raw)) return null;
  return TagFolder(raw);
}
