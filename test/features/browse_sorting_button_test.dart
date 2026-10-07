import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_sorting_button.dart';

const List<Sorting> _sortings = <Sorting>[
  Sorting.dateAdded,
  Sorting.toplist,
  Sorting.hot,
];

Future<TabController> _pump(
  WidgetTester tester, {
  Size screen = const Size(800, 600),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final TabController tabs = TabController(
    length: _sortings.length,
    vsync: const TestVSync(),
  );
  addTearDown(tabs.dispose);
  await tester.pumpWidget(
    MaterialApp(
      // The app's theme: it is what opens menus under their button.
      theme: TelaTheme.dark(null),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: CapsuleActionCluster(
            children: <Widget>[
              BrowseSortingButton(tabs: tabs, sortings: _sortings),
            ],
          ),
        ),
      ),
    ),
  );
  return tabs;
}

void main() {
  group('BrowseSortingButton', () {
    testWidgets('names the sorting on screen', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('Latest'), findsOneWidget);
      expect(find.byTooltip('Sorted by Latest'), findsOneWidget);
    });

    testWidgets('picking from the menu moves the listing', (
      WidgetTester tester,
    ) async {
      final TabController tabs = await _pump(tester);

      await tester.tap(find.byType(BrowseSortingButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Hot'));
      await tester.pumpAndSettle();

      expect(tabs.index, 2);
      expect(find.text('Hot'), findsOneWidget);
    });

    testWidgets('follows a swipe made elsewhere', (WidgetTester tester) async {
      final TabController tabs = await _pump(tester);

      tabs.index = 1;
      await tester.pump();

      expect(find.text('Top'), findsOneWidget);
    });

    testWidgets('a phone gets the icon alone, still named by its tooltip', (
      WidgetTester tester,
    ) async {
      await _pump(tester, screen: const Size(360, 800));

      expect(find.text('Latest'), findsNothing);
      expect(find.byIcon(Icons.sort), findsOneWidget);
      expect(find.byTooltip('Sorted by Latest'), findsOneWidget);
    });

    testWidgets('the menu opens below the capsule, not over its edge', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byType(BrowseSortingButton));
      await tester.pumpAndSettle();

      final double capsuleBottom = tester
          .getBottomLeft(find.byType(CapsuleActionCluster))
          .dy;
      final double menuTop = tester
          .getTopLeft(
            find
                .ancestor(
                  of: find.widgetWithText(CheckedPopupMenuItem<int>, 'Top'),
                  matching: find.byType(Material),
                )
                .last,
          )
          .dy;
      expect(menuTop, greaterThanOrEqualTo(capsuleBottom));
    });
  });
}
