import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/core/ui/tela_mark.dart';
import 'package:tela/core/ui/tela_wordmark.dart';

/// The adaptive frame around tela's three primary destinations.
///
/// Compact screens keep destinations thumb-reachable at the bottom. Wider
/// screens move the same destinations into a rail so the wallpaper canvas can
/// use the extra width instead of growing an oversized bottom bar.
///
/// Both float: the bar is a pill and the rail a rounded panel, each a
/// [FloatingCapsule] inset on the opaque surface. The wall stops at that
/// surface — nothing scrolls under the navigation (see [FloatingCapsule] for
/// why tela's chrome is never glass).
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
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: FloatingCapsule(
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            height: 64,
            selectedIndex: navigationShell.currentIndex,
            destinations: _bottomDestinations(context),
            onDestinationSelected: _openDestination,
          ),
        ),
      ),
    );
  }

  Widget _expandedFrame(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          _floatingRail(context),
          // A semantics boundary around the branch, or the rail vanishes for
          // TalkBack: every page route carries a ModalBarrier, whose
          // BlockSemantics drops all nodes painted before it up to the nearest
          // boundary — and the rail is painted first, in this same Row (device
          // pass F5, 2026-10-03). The bottom bar escapes only by being painted
          // after the body.
          Expanded(
            child: Semantics(container: true, child: navigationShell),
          ),
        ],
      ),
    );
  }

  /// The rail panel, as tall as its contents and no taller.
  ///
  /// It ran the full height of the screen, so in tablet landscape three
  /// destinations sat at the top of a panel that was empty below them — the
  /// owner: *"the three buttons waste so much space on the bottom, like in
  /// portrait it sits flush"* (2026-10-05). Portrait gets the bottom pill,
  /// which hugs its destinations; this is the same shape turned on its side.
  /// Top-aligned, so the brand stays level with the search row beside it.
  Widget _floatingRail(BuildContext context) {
    return SafeArea(
      right: false,
      minimum: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: IntrinsicHeight(child: _railPanel(context)),
      ),
    );
  }

  Widget _railPanel(BuildContext context) {
    return FloatingCapsule(
      radius: 28,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: navigationShell.currentIndex,
        labelType: NavigationRailLabelType.all,
        leading: const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 28),
          child: _RailBrand(),
        ),
        destinations: _railDestinations(context),
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

/// The rail's brand lockup: the mark stacked over the wordmark.
///
/// Stacked rather than side by side because the rail is narrow — a horizontal
/// lockup would either shrink the wordmark below reading size or push the rail
/// wider, and the rail exists to give width back to the wall.
///
/// The lockup is private to the rail: it is the only place in the app that
/// shows both, so a shared widget would be speculative. [TelaMark] and
/// [TelaWordmark] are the shared pieces.
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TelaMark(size: 30),
        SizedBox(height: 10),
        TelaWordmark(fontSize: 20),
      ],
    );
  }
}
