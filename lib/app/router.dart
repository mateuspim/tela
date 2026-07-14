import 'package:go_router/go_router.dart';
import 'package:tela/features/browse/browse_screen.dart';

/// The app's routes.
///
/// One route for now (Wave 0). Detail, search, favorites and settings hang off
/// this as Wave 1 lands; keeping the router separate from the app widget means
/// adding them touches this file only.
abstract final class TelaRouter {
  /// Path of the browse grid, the app's home.
  static const String browsePath = '/';

  /// Builds the router.
  static GoRouter create() {
    return GoRouter(
      initialLocation: browsePath,
      routes: <RouteBase>[
        GoRoute(
          path: browsePath,
          name: 'browse',
          builder: (_, _) => const BrowseScreen(),
        ),
      ],
    );
  }
}
