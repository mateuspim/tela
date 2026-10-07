import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/floating_capsule.dart';

/// The frame around tela's three primary destinations: one floating pill at
/// the bottom, at every width.
///
/// The pill is an opaque [FloatingCapsule] (see there for why tela's chrome is
/// never glass), but the strip around it is not a solid band: the wall runs
/// on beneath it, under a veil of the surface that fades in from clear to
/// [veilOpacity]. The owner asked for the pictures to *"naturally scroll"*
/// past the bar rather than stop at a hard edge (2026-10-06), relaxing the
/// "nothing scrolls under the chrome" rule for this one strip. The pill itself
/// stays solid, so its labels never sit on a photo. The wall still ends clear
/// of it: `extendBody` hands the strip's height to the branch as bottom
/// padding, which every scrolling list here already honours.
///
/// Wide screens used to swap the pill for a side rail. In tablet landscape
/// that spent a whole column of the screen on three buttons, and however the
/// panel sat in it — full height, hugging the top, centred — the column read
/// as blank space (owner, 2026-10-06: *"i still think there is too many blank
/// space"*). The pill costs a strip of height instead and gives the wall the
/// full width; portrait already had it and the owner liked it there.
class TelaShell extends StatelessWidget {
  /// Creates the primary navigation shell.
  const TelaShell({required this.navigationShell, super.key});

  /// go_router's stateful stack for each primary destination.
  final StatefulNavigationShell navigationShell;

  /// The widest the pill grows. Tablet portrait (~753dp) keeps its
  /// full-width pill; landscape stops here, centred, rather than stretching
  /// three destinations across 1200dp.
  static const double navigationMaxWidth = 760;

  /// How much of the surface the veil under the pill lays over the wall at
  /// its densest. Half: the owner's *"like a 50% transparent"*.
  static const double veilOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Stack(
        children: <Widget>[
          const Positioned.fill(child: _NavigationVeil()),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: navigationMaxWidth,
                ),
                child: _navigationPill(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigationPill(BuildContext context) {
    return FloatingCapsule(
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        height: 64,
        selectedIndex: navigationShell.currentIndex,
        destinations: _bottomDestinations(context),
        onDestinationSelected: _openDestination,
      ),
    );
  }

  List<NavigationDestination> _bottomDestinations(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.grid_view_outlined),
        selectedIcon: const Icon(Icons.grid_view_rounded),
        label: l10n.navigationBrowse,
      ),
      NavigationDestination(
        icon: const Icon(Icons.photo_library_outlined),
        selectedIcon: const Icon(Icons.photo_library),
        label: l10n.navigationLibrary,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.settingsTitle,
      ),
    ];
  }

  void _openDestination(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// The surface fading in behind the pill, so the wall dims as it passes
/// under the navigation instead of being cut at a hard edge.
///
/// Ignores pointers: a decoration claims every hit inside its box, and the
/// strip beside the pill would otherwise swallow taps meant for the wall.
class _NavigationVeil extends StatelessWidget {
  const _NavigationVeil();

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.4],
            colors: <Color>[
              surface.withValues(alpha: 0),
              surface.withValues(alpha: TelaShell.veilOpacity),
            ],
          ),
        ),
      ),
    );
  }
}
