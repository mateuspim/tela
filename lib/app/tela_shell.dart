import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// The adaptive frame around tela's three primary destinations.
///
/// Compact screens keep destinations thumb-reachable at the bottom. Wider
/// screens move the same destinations into a rail so the wallpaper canvas can
/// use the extra width instead of growing an oversized bottom bar.
class TelaShell extends StatelessWidget {
  /// Creates the primary navigation shell.
  const TelaShell({required this.navigationShell, super.key});

  /// go_router's stateful stack for each primary destination.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= expandedNavigationWidth) {
          return _expandedFrame(context);
        }
        return _compactFrame(context);
      },
    );
  }

  /// Width at which persistent navigation moves from the bottom to the side.
  static const double expandedNavigationWidth = 840;

  Widget _compactFrame(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: _bottomDestinations(context),
        onDestinationSelected: _openDestination,
      ),
    );
  }

  Widget _expandedFrame(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  l10n.appTitle.substring(0, 1),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            destinations: _railDestinations(context),
            onDestinationSelected: _openDestination,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
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

  List<NavigationRailDestination> _railDestinations(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.grid_view_outlined),
        selectedIcon: const Icon(Icons.grid_view_rounded),
        label: Text(l10n.navigationBrowse),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.photo_library_outlined),
        selectedIcon: const Icon(Icons.photo_library),
        label: Text(l10n.navigationLibrary),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(l10n.settingsTitle),
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
