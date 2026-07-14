import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/browse_screen.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';
import 'package:tela/features/settings/settings_screen.dart';

/// The app's routes.
///
/// Browse, detail, and settings are live. Search and favorites hang off this as
/// later slices land; keeping the router separate from the app widget means
/// adding them touches this file only.
abstract final class TelaRouter {
  /// Builds the router.
  static GoRouter create() {
    return GoRouter(
      initialLocation: TelaRoutes.browsePath,
      routes: <RouteBase>[
        GoRoute(
          path: TelaRoutes.browsePath,
          name: TelaRoutes.browseName,
          builder: (_, _) => const BrowseScreen(),
        ),
        GoRoute(
          path: TelaRoutes.detailPath,
          name: TelaRoutes.detailName,
          redirect: (_, GoRouterState state) =>
              state.extra is Wallpaper ? null : TelaRoutes.browsePath,
          builder: (_, GoRouterState state) => WallpaperDetailScreen(
            wallpaper: state.extra! as Wallpaper,
          ),
        ),
        GoRoute(
          path: TelaRoutes.settingsPath,
          name: TelaRoutes.settingsName,
          builder: (_, _) => const SettingsScreen(),
        ),
      ],
    );
  }
}
