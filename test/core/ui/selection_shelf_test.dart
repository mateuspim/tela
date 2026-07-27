import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';

/// Tall enough that a shelf of them scrolls well past its viewport.
const double _rowHeight = 100;
const int _rowCount = 60;

/// Far enough down that the top of the list is nowhere on screen, so a reset
/// to zero cannot be mistaken for a small correction.
const double _scrollTo = 1200;

/// The contextual bar's own icon, and the only reliable way to ask whether the
/// shelf is selecting from outside it — `_SelectionBar` is private.
final Finder _selectionBar = find.byIcon(Icons.select_all);

/// The shelf as a screen mounts it: the scope above the `Scaffold`, the
/// *Select* button in the app bar, the bar wrapping the scrolling child.
Widget _host({
  ScrollController? controller,
  bool expandChild = true,
  bool withScope = true,
}) {
  final Widget shelf = SelectionShelf(
    itemIds: <String>[for (int i = 0; i < _rowCount; i++) 'item $i'],
    actions: const <SelectionAction>[],
    expandChild: expandChild,
    child: ListView.builder(
      controller: controller,
      itemCount: _rowCount,
      itemBuilder: (BuildContext context, int index) =>
          SizedBox(height: _rowHeight, child: Text('item $index')),
    ),
  );
  final Widget screen = Scaffold(
    appBar: AppBar(actions: const <Widget>[SelectModeButton()]),
    body: shelf,
  );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: withScope ? SelectionShelfScope(child: screen) : screen,
  );
}

void main() {
  group('SelectionShelf', () {
    testWidgets('entering selection leaves the shelf where it was scrolled', (
      WidgetTester tester,
    ) async {
      // The bug this pins (owner, on device): starting a multi-select threw
      // the wall back to the top, so picking a second wallpaper meant
      // scrolling all the way down again. The cause was structural — the shelf
      // swapped its child for a `Column` when the mode began, which is a
      // different widget at that slot, so the whole grid subtree was rebuilt
      // from scratch and the scroll position went with it.
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller: controller));
      controller.jumpTo(_scrollTo);
      await tester.pump();
      expect(_selectionBar, findsNothing, reason: 'not selecting yet');

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(_selectionBar, findsOneWidget, reason: 'the bar must have opened');
      expect(controller.offset, _scrollTo);
      expect(find.text('item 12'), findsOneWidget);
    });

    testWidgets('a shelf with no controller of its own keeps its place', (
      WidgetTester tester,
    ) async {
      // Three of the four shelves — Favorites, Download History and the private
      // library — pass no `ScrollController` at all and scroll on the one
      // `ListView` makes for itself. There is no offset to read there, so this
      // asks the question the way a user does: is the same row still under the
      // same pixel afterwards?
      await tester.pumpWidget(_host());
      await tester.drag(find.text('item 0'), const Offset(0, -_scrollTo));
      await tester.pump();
      final Offset before = tester.getTopLeft(find.text('item 14'));

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(_selectionBar, findsOneWidget);
      // Only the bar's own height may move it, and the bar is above the shelf.
      expect(tester.getTopLeft(find.text('item 14')).dx, before.dx);
      expect(find.text('item 0'), findsNothing, reason: 'must not be at top');
    });

    testWidgets('leaving selection leaves it where it was scrolled too', (
      WidgetTester tester,
    ) async {
      // The way out has the same shape as the way in, and a jump on cancel
      // would be just as costly: it lands after the batch action ran.
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller: controller));
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      controller.jumpTo(_scrollTo);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(_selectionBar, findsNothing, reason: 'the bar must have closed');
      expect(controller.offset, _scrollTo);
    });

    testWidgets('a fixed-height strip keeps its offset as well', (
      WidgetTester tester,
    ) async {
      // `expandChild: false` is the Library hub's downloads strip, which sits
      // in an unbounded column. It takes the other branch of the layout, so it
      // needs its own proof that the branch does not rebuild the shelf either.
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SelectionShelfScope(
            child: Scaffold(
              appBar: AppBar(actions: const <Widget>[SelectModeButton()]),
              body: ListView(
                children: <Widget>[
                  SelectionShelf(
                    itemIds: const <String>['a'],
                    actions: const <SelectionAction>[],
                    expandChild: false,
                    child: SizedBox(
                      height: 200,
                      child: ListView.builder(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        itemCount: _rowCount,
                        itemBuilder: (BuildContext context, int index) =>
                            SizedBox(width: _rowHeight, child: Text('$index')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(_scrollTo);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(_selectionBar, findsOneWidget);
      expect(controller.offset, _scrollTo);
    });

    testWidgets('draws its child alone with no scope above it', (
      WidgetTester tester,
    ) async {
      // The same courtesy the scopes extend: a shelf mounted on its own in a
      // widget test renders, rather than throwing or showing a bar it cannot
      // drive.
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller: controller, withScope: false));

      expect(find.text('item 0'), findsOneWidget);
      expect(_selectionBar, findsNothing);
      expect(find.byIcon(Icons.checklist), findsNothing);
    });

    testWidgets('ticking an item does not move the shelf', (
      WidgetTester tester,
    ) async {
      // Every tick rebuilds the shelf through the inherited notifier, so the
      // structure has to be stable across a toggle and not merely across the
      // mode change.
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller: controller));
      final WallpaperSelection selection = WallpaperSelectionScope.of(
        tester.element(find.text('item 0')),
      )!..enter();
      await tester.pump();
      controller.jumpTo(_scrollTo);
      await tester.pump();

      selection.toggle('item 13');
      await tester.pump();

      expect(controller.offset, _scrollTo);
    });
  });
}
