import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

/// C4 — the tile marks: "you already have this", read from one set-shaped
/// scope rather than a per-tile provider watch.
void main() {
  group('WallpaperMarksScope.marksFor', () {
    testWidgets('answers nothing with no scope above it', (
      WidgetTester tester,
    ) async {
      // The claim that let every pre-C4 shelf test keep passing untouched: a
      // shelf mounted on its own draws unmarked tiles rather than throwing.
      late Set<WallpaperMark> marks;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            marks = WallpaperMarksScope.marksFor(
              context,
              'abc',
              WallpaperMark.values.toSet(),
            );
            return const SizedBox.shrink();
          },
        ),
      );

      expect(marks, isEmpty);
    });

    testWidgets('reports only the marks the wallpaper has earned', (
      WidgetTester tester,
    ) async {
      late Set<WallpaperMark> both;
      late Set<WallpaperMark> onlyDownloaded;
      late Set<WallpaperMark> neither;
      await tester.pumpWidget(
        WallpaperMarksScope(
          favorited: const <String>{'fav'},
          downloaded: const <String>{'fav', 'dl'},
          child: Builder(
            builder: (BuildContext context) {
              Set<WallpaperMark> ask(String id) => WallpaperMarksScope.marksFor(
                context,
                id,
                WallpaperMark.values.toSet(),
              );
              both = ask('fav');
              onlyDownloaded = ask('dl');
              neither = ask('stranger');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(both, <WallpaperMark>{
        WallpaperMark.favorited,
        WallpaperMark.downloaded,
      });
      expect(onlyDownloaded, <WallpaperMark>{WallpaperMark.downloaded});
      expect(neither, isEmpty);
    });

    testWidgets('a shelf can suppress a mark it would draw on every tile', (
      WidgetTester tester,
    ) async {
      // Favorites and the download history each narrow this, so the one mark
      // that is true of the whole shelf does not become decoration.
      late Set<WallpaperMark> narrowed;
      await tester.pumpWidget(
        WallpaperMarksScope(
          favorited: const <String>{'x'},
          downloaded: const <String>{'x'},
          child: Builder(
            builder: (BuildContext context) {
              narrowed = WallpaperMarksScope.marksFor(
                context,
                'x',
                const <WallpaperMark>{WallpaperMark.downloaded},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(narrowed, <WallpaperMark>{WallpaperMark.downloaded});
    });

    test('notifies on a set whose contents changed, not its identity', () {
      // Both sets are rebuilt from scratch every provider recompute, so an
      // identity check here would re-mark the whole wall on every rebuild.
      //
      // [fresh] exists so these sets cannot be const. Dart canonicalizes equal
      // const sets to a single instance, so a const `sameContents` would be
      // *identical* to `original` and an identity-based `updateShouldNotify`
      // would pass — the mutation this test exists to catch would go unseen.
      // Building through a spread also matches production, where each set is a
      // new object every time its provider recomputes.
      Set<String> fresh(List<String> ids) => <String>{...ids};
      const Widget child = SizedBox.shrink();
      final WallpaperMarksScope original = WallpaperMarksScope(
        favorited: fresh(<String>['a']),
        downloaded: fresh(<String>[]),
        child: child,
      );
      final WallpaperMarksScope sameContents = WallpaperMarksScope(
        favorited: fresh(<String>['a']),
        downloaded: fresh(<String>[]),
        child: child,
      );
      final WallpaperMarksScope changed = WallpaperMarksScope(
        favorited: fresh(<String>['a', 'b']),
        downloaded: fresh(<String>[]),
        child: child,
      );

      expect(sameContents.updateShouldNotify(original), isFalse);
      expect(changed.updateShouldNotify(original), isTrue);
    });
  });

  group('WallpaperTile marks', () {
    testWidgets('draws a heart for a favorited wallpaper and none otherwise', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          favorited: const <String>{'fav'},
          downloaded: const <String>{},
          children: <Widget>[
            WallpaperTile(wallpaper: _wallpaper('fav')),
            WallpaperTile(wallpaper: _wallpaper('plain')),
          ],
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.download_done), findsNothing);
    });

    testWidgets('a doubly-marked tile carries both icons in one pill', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          favorited: const <String>{'both'},
          downloaded: const <String>{'both'},
          children: <Widget>[WallpaperTile(wallpaper: _wallpaper('both'))],
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.download_done), findsOneWidget);
      // One pill, not one per mark — otherwise the corner grows two chips.
      expect(
        find.descendant(of: find.byType(Tooltip), matching: find.byType(Icon)),
        findsNWidgets(2),
      );
    });

    testWidgets('visibleMarks drops the mark the shelf does not want', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          favorited: const <String>{'x'},
          downloaded: const <String>{'x'},
          children: <Widget>[
            WallpaperTile(
              wallpaper: _wallpaper('x'),
              visibleMarks: const <WallpaperMark>{WallpaperMark.downloaded},
            ),
          ],
        ),
      );

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.download_done), findsOneWidget);
    });

    testWidgets('the mark stays outside the Hero', (WidgetTester tester) async {
      // A mark inside the Hero flies into the detail screen with the thumbnail
      // and lands on top of the full preview. This is the test that catches it.
      await tester.pumpWidget(
        _host(
          favorited: const <String>{'fav'},
          downloaded: const <String>{},
          children: <Widget>[
            WallpaperTile(wallpaper: _wallpaper('fav'), heroTag: 'tag-fav'),
          ],
        ),
      );

      expect(find.byType(Hero), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Hero),
          matching: find.byIcon(Icons.favorite),
        ),
        findsNothing,
      );
    });
  });
}

/// A minimal shelf: localized, themed, and under a marks scope.
Widget _host({
  required Set<String> favorited,
  required Set<String> downloaded,
  required List<Widget> children,
}) {
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: WallpaperMarksScope(
      favorited: favorited,
      downloaded: downloaded,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: 200, height: 200, child: child),
          ],
        ),
      ),
    ),
  );
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  fullImageUrl: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
