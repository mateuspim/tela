import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/app.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/tela_shell.dart';
import 'package:tela/core/ui/floating_capsule.dart';

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

  testWidgets('a wide screen keeps the bottom pill, never a rail', (
    WidgetTester tester,
  ) async {
    // A side rail spent a column on three buttons in tablet landscape, read
    // as blank space (owner, 2026-10-06).
    _setView(tester, const Size(1280, 800));

    await _pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('the pill stops growing in landscape, centred', (
    WidgetTester tester,
  ) async {
    _setView(tester, const Size(1280, 800));

    await _pumpShell(tester);

    final Rect pill = tester.getRect(_pill());
    expect(pill.width, TelaShell.navigationMaxWidth);
    expect(pill.center.dx, 640);
  });

  testWidgets('tablet portrait keeps its full-width pill', (
    WidgetTester tester,
  ) async {
    _setView(tester, const Size(753, 1205));

    await _pumpShell(tester);

    expect(tester.getRect(_pill()).width, 753 - 32);
  });

  testWidgets('the wall runs on under a half veil, ending clear of the pill', (
    WidgetTester tester,
  ) async {
    // The owner wants pictures to scroll past the bar, not stop at it
    // (2026-10-06).
    _setView(tester, const Size(1280, 800));

    await _pumpShell(tester);

    final Scaffold frame = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    expect(frame.extendBody, isTrue);

    final DecoratedBox veil = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.ancestor(
              of: find.byType(NavigationBar),
              matching: find.byType(Stack),
            ),
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).gradient != null,
            ),
          )
          .first,
    );
    final LinearGradient fade =
        (veil.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(fade.colors.first.a, 0);
    expect(fade.colors.last.a, closeTo(TelaShell.veilOpacity, 0.01));

    // The branch is told how tall the strip is, so its last row can scroll
    // up above the pill.
    final double inset = MediaQuery.paddingOf(
      tester.element(find.byType(StatefulNavigationShell)),
    ).bottom;
    expect(inset, greaterThanOrEqualTo(tester.getRect(_pill()).height));
  });

  testWidgets('the destinations reach the accessibility tree', (
    WidgetTester tester,
  ) async {
    // Disposed in the body, not by addTearDown: flutter_test checks for a live
    // handle before tear-downs run.
    final SemanticsHandle semantics = tester.ensureSemantics();
    _setView(tester, const Size(1280, 800));

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
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _pill() {
  return find.ancestor(
    of: find.byType(NavigationBar),
    matching: find.byType(FloatingCapsule),
  );
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
