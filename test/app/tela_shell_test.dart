import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/tela_shell.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/core/ui/tela_mark.dart';
import 'package:tela/core/ui/tela_wordmark.dart';

import '../fakes/fake_download_queue.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

void main() {
  testWidgets('uses thumb-reachable navigation on a compact screen', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    final Finder library = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Library'),
    );
    await tester.tap(library);
    await tester.pumpAndSettle();

    // The Library tab opens on its favorites shelf, empty here.
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('moves primary navigation to a rail on a wide screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShell(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(TelaShell.expandedNavigationWidth, 840);
  });

  testWidgets('the rail panel hugs its destinations, not the screen height', (
    WidgetTester tester,
  ) async {
    // Tablet landscape: three destinations at the top of a full-height panel,
    // empty below them (owner, 2026-10-05).
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShell(tester);

    final Rect panel = tester.getRect(
      find
          .ancestor(
            of: find.byType(NavigationRail),
            matching: find.byType(FloatingCapsule),
          )
          .first,
    );
    final Rect settings = tester.getRect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Settings'),
      ),
    );
    expect(panel.height, lessThan(800 / 2));
    expect(panel.bottom, greaterThan(settings.bottom));
    expect(panel.bottom - settings.bottom, lessThan(48));
  });

  // Device pass F5 (2026-10-03): on the SM-X730 the rail's three destinations
  // were missing from the accessibility tree uiautomator reads, so TalkBack
  // could not reach them — a page route's BlockSemantics wiped them. Searched
  // in the live semantics tree, as an accessibility service sees it, rather
  // than asked of the widget's own node.
  testWidgets('the rail destinations reach the accessibility tree', (
    WidgetTester tester,
  ) async {
    // Disposed in the body, not by addTearDown: flutter_test checks for a live
    // handle before tear-downs run.
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShell(tester);

    for (final String destination in <String>[
      'Browse',
      'Library',
      'Settings',
    ]) {
      expect(
        find.semantics.byPredicate(
          (SemanticsNode node) =>
              node.label.contains(destination) &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        ),
        findsAtLeast(1),
        reason: '$destination is not reachable by an accessibility service',
      );
    }
    semantics.dispose();
  });

  testWidgets('the rail leads with the brand lockup: mark over wordmark', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShell(tester);

    final Finder rail = find.byType(NavigationRail);
    expect(
      find.descendant(of: rail, matching: find.byType(TelaMark)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.byType(TelaWordmark)),
      findsOneWidget,
    );
    // Stacked, not side by side — the rail is narrow, and a horizontal lockup
    // would either shrink the wordmark below reading size or widen the rail
    // at the wall's expense.
    expect(
      tester.getCenter(find.byType(TelaMark)).dy,
      lessThan(tester.getCenter(find.byType(TelaWordmark)).dy),
    );
  });
}

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(FakeWallpaperSource()),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
        downloadQueueProvider.overrideWithValue(FakeDownloadQueue()),
      ],
      child: const TelaApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
