import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_swatch.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/features/detail/wallpaper_metadata.dart';

void main() {
  testWidgets("tapping a dominant colour follows that colour's listing", (
    WidgetTester tester,
  ) async {
    // The swatches were labels until now; a tap must open "more in this colour"
    // the same way a tag chip opens its tag — through onFollow, as a ColorLink.
    WallpaperLink? followed;
    await _pumpMetadata(
      tester,
      onFollow: (WallpaperLink link) {
        followed = link;
      },
    );

    await tester.tap(find.byType(WallpaperSwatch).first);

    expect(followed, ColorLink(WallpaperColor('#0066cc')));
  });

  testWidgets('a URL source opens outside tela', (WidgetTester tester) async {
    Uri? opened;
    await _pumpMetadata(tester, onOpenLink: (Uri url) => opened = url);

    await tester.tap(find.text('https://example.com/source'));

    expect(opened, Uri.parse('https://example.com/source'));
  });

  testWidgets('View on Wallhaven opens the wallpaper page', (
    WidgetTester tester,
  ) async {
    Uri? opened;
    await _pumpMetadata(tester, onOpenLink: (Uri url) => opened = url);

    await tester.tap(find.text('View on Wallhaven'));

    expect(opened, Uri.parse('https://wallhaven.cc/w/e7jvjd'));
  });

  testWidgets('every scalar fact is a tile, not a key-value row', (
    WidgetTester tester,
  ) async {
    // The panel spoke two languages for one kind of data: resolution, size,
    // category and purity were cards while file type, ratio, views and
    // favorites were a plain list below them. All eight are tiles now.
    await _pumpMetadata(tester);

    for (final String label in <String>[
      'Resolution',
      'File size',
      'Category',
      'Purity',
      'File type',
      'Ratio',
      'Views',
      'Favorites',
    ]) {
      expect(
        find.byKey(Key('metadata-fact-$label')),
        findsOneWidget,
        reason: '$label must render as a fact tile',
      );
    }
  });

  testWidgets('the colours sit above the attribution links and the tags', (
    WidgetTester tester,
  ) async {
    // Reachability, not taste: the swatches used to sit at the panel's clipped
    // bottom edge, and the 2026-07-18 device pass could not verify the colour
    // drilldown at all because the tap landed in the gutter below them.
    await _pumpMetadata(tester);

    final double swatches = tester.getTopLeft(find.byType(WallpaperSwatch)).dy;

    expect(swatches, lessThan(tester.getTopLeft(find.text('tela-fixture')).dy));
    expect(swatches, lessThan(tester.getTopLeft(find.text('Tags')).dy));
  });

  testWidgets('a non-URL source stays plain, copyable text', (
    WidgetTester tester,
  ) async {
    // Wallhaven's source is free text: a bare attribution must not become a
    // link that opens nothing. It stays SelectableText, so it can be copied.
    await _pumpMetadata(tester, source: 'Photographer: Jane Doe');

    expect(
      find.widgetWithText(SelectableText, 'Photographer: Jane Doe'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpMetadata(
  WidgetTester tester, {
  ValueChanged<WallpaperLink>? onFollow,
  ValueChanged<Uri>? onOpenLink,
  String source = 'https://example.com/source',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: WallpaperMetadata(
            details: _details(source: source),
            onFollow: onFollow ?? (_) {},
            onBlockTag: (_) {},
            onOpenLink: onOpenLink ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

WallpaperDetails _details({String source = 'https://example.com/source'}) =>
    WallpaperDetails(
      wallpaper: const Wallpaper(
        id: 'e7jvjd',
        fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
        thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
        thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
        thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
        resolution: Resolution(3840, 2160),
        fileSizeBytes: 1048576,
        purity: Purity.sfw,
        category: Category.general,
        colors: <String>['#0066cc'],
      ),
      ratio: '1.78',
      fileType: 'image/jpeg',
      tags: const <WallpaperTag>[WallpaperTag(id: 101, name: 'landscape')],
      uploader: const WallpaperUploader(
        username: 'tela-fixture',
        group: 'User',
        avatarUrl: 'https://example.com/avatar.jpg',
      ),
      source: source,
      views: 4523,
      favorites: 128,
    );
