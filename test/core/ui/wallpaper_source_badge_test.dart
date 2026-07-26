import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_source_badge.dart';
import 'package:tela/core/ui/wallpaper_source_labels_scope.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

/// The source badge: a library tile names which site its wallpaper came from,
/// read from one root-level scope rather than a per-tile provider watch.
void main() {
  group('WallpaperSourceLabelsScope.labelFor', () {
    testWidgets('answers null with no scope above it', (
      WidgetTester tester,
    ) async {
      // The same graceful-empty the marks scope gives: a shelf mounted alone
      // draws no badge rather than throwing, so no existing test needs a scope.
      late String? name;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            name = WallpaperSourceLabelsScope.labelFor(context, 'wallhaven');
            return const SizedBox.shrink();
          },
        ),
      );

      expect(name, isNull);
    });

    testWidgets('maps a known id and answers null for an unknown one', (
      WidgetTester tester,
    ) async {
      late String? known;
      late String? unknown;
      await tester.pumpWidget(
        WallpaperSourceLabelsScope(
          labels: const <String, String>{
            'wallhaven': 'Wallhaven',
            'konachan': 'Konachan',
          },
          child: Builder(
            builder: (BuildContext context) {
              known = WallpaperSourceLabelsScope.labelFor(context, 'konachan');
              // A source a downgraded build no longer has: null draws no badge
              // rather than a raw lowercase id.
              unknown = WallpaperSourceLabelsScope.labelFor(context, 'yandere');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(known, 'Konachan');
      expect(unknown, isNull);
    });

    test('notifies on a map whose contents changed, not its identity', () {
      // The map is rebuilt from the registry on every unrelated root rebuild,
      // so an identity check would re-badge the whole wall each time.
      Map<String, String> fresh(Map<String, String> entries) =>
          <String, String>{...entries};
      const Widget child = SizedBox.shrink();
      final WallpaperSourceLabelsScope original = WallpaperSourceLabelsScope(
        labels: fresh(const <String, String>{'wallhaven': 'Wallhaven'}),
        child: child,
      );
      final WallpaperSourceLabelsScope sameContents =
          WallpaperSourceLabelsScope(
            labels: fresh(const <String, String>{'wallhaven': 'Wallhaven'}),
            child: child,
          );
      final WallpaperSourceLabelsScope changed = WallpaperSourceLabelsScope(
        labels: fresh(const <String, String>{
          'wallhaven': 'Wallhaven',
          'konachan': 'Konachan',
        }),
        child: child,
      );

      expect(sameContents.updateShouldNotify(original), isFalse);
      expect(changed.updateShouldNotify(original), isTrue);
    });
  });

  group('WallpaperSourceBadge', () {
    testWidgets('shows the source name and a fuller accessibility label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const WallpaperSourceBadge(sourceName: 'Konachan')),
      );

      // The pill reads the bare name; the screen reader hears "From Konachan"
      // so a floating "Konachan" is not left cryptic.
      expect(find.text('Konachan'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.text('Konachan'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .label,
        'From Konachan',
      );
    });
  });

  group('WallpaperTile source badge', () {
    testWidgets("a library shelf names each tile's source", (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          children: <Widget>[
            WallpaperTile(
              wallpaper: _wallpaper('a', SourceId.wallhaven),
              showSourceBadge: true,
            ),
            WallpaperTile(
              wallpaper: _wallpaper('b', SourceId.konachan),
              showSourceBadge: true,
            ),
          ],
        ),
      );

      expect(find.byType(WallpaperSourceBadge), findsNWidgets(2));
      expect(find.text('Wallhaven'), findsOneWidget);
      expect(find.text('Konachan'), findsOneWidget);
    });

    testWidgets('the browse wall shows no badge (single source says nothing)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          children: <Widget>[
            WallpaperTile(wallpaper: _wallpaper('a', SourceId.konachan)),
          ],
        ),
      );

      expect(find.byType(WallpaperSourceBadge), findsNothing);
    });

    testWidgets('no badge when the source name is not in scope', (
      WidgetTester tester,
    ) async {
      // A build that lacks the labels scope, or a source retired since a row
      // was written, draws nothing rather than a raw id.
      await tester.pumpWidget(
        _host(
          includeLabels: false,
          children: <Widget>[
            WallpaperTile(
              wallpaper: _wallpaper('a', SourceId.wallhaven),
              showSourceBadge: true,
            ),
          ],
        ),
      );

      expect(find.byType(WallpaperSourceBadge), findsNothing);
    });

    testWidgets('the badge stays outside the Hero', (
      WidgetTester tester,
    ) async {
      // Like the marks: a badge inside the Hero would fly into the detail
      // screen with the thumbnail and land on top of the full preview.
      await tester.pumpWidget(
        _host(
          children: <Widget>[
            WallpaperTile(
              wallpaper: _wallpaper('a', SourceId.konachan),
              heroTag: 'tag-a',
              showSourceBadge: true,
            ),
          ],
        ),
      );

      expect(find.byType(Hero), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Hero),
          matching: find.byType(WallpaperSourceBadge),
        ),
        findsNothing,
      );
    });
  });
}

/// Localizes and themes a lone widget under test.
Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

/// A minimal shelf: localized, themed, and under both wall scopes.
Widget _host({
  required List<Widget> children,
  bool includeLabels = true,
}) {
  Widget wall = WallpaperMarksScope(
    favorited: const <String>{},
    downloaded: const <String>{},
    child: Scaffold(
      body: Column(
        children: <Widget>[
          for (final Widget child in children)
            SizedBox(width: 200, height: 200, child: child),
        ],
      ),
    ),
  );
  if (includeLabels) {
    wall = WallpaperSourceLabelsScope(
      labels: const <String, String>{
        'wallhaven': 'Wallhaven',
        'konachan': 'Konachan',
      },
      child: wall,
    );
  }
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: wall,
  );
}

Wallpaper _wallpaper(String id, SourceId source) => Wallpaper(
  id: id,
  source: source,
  pageUrl: Uri.parse('https://example.test/w/$id'),
  fullImageUrl: 'https://example.test/full/$id.jpg',
  thumbSmallUrl: 'https://example.test/small/$id.jpg',
  thumbLargeUrl: 'https://example.test/lg/$id.jpg',
  thumbOriginalUrl: 'https://example.test/orig/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
