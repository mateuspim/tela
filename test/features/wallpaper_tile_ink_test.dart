import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';

Wallpaper _wallpaper() => Wallpaper(
  id: 'e7jvjd',
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(3840, 2160),
  fileSizeBytes: 1048576,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>['#660000'],
);

Future<void> _pumpTile(WidgetTester tester, {VoidCallback? onTap}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 120,
            child: WallpaperTile(wallpaper: _wallpaper(), onTap: onTap),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('splashes above the thumbnail, not beneath it', (
    WidgetTester tester,
  ) async {
    // A Material paints its ink layer *beneath* its child, so an InkWell
    // wrapped around an opaque `BoxFit.cover` image — which is every tile on
    // every shelf — splashed under the wallpaper and could not be seen:
    // pressing a tile gave no feedback at all. Put the InkWell back around the
    // thumbnail and this test names it.
    await _pumpTile(tester, onTap: () {});

    expect(
      find.ancestor(
        of: find.byType(CachedNetworkImage),
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason: 'an InkWell above the image paints its splash below the image',
    );
  });

  testWidgets('puts the ink on a Material of its own', (
    WidgetTester tester,
  ) async {
    // The splash needs *a* Material to paint on; a bare InkWell over the image
    // would throw. It has to be a transparent one, or it would hide the
    // wallpaper it sits on.
    await _pumpTile(tester, onTap: () {});

    final Material inkSurface = tester.widget<Material>(
      find
          .ancestor(of: find.byType(InkWell), matching: find.byType(Material))
          .first,
    );
    expect(inkSurface.type, MaterialType.transparency);
  });

  testWidgets('still reports the tap it was given', (
    WidgetTester tester,
  ) async {
    // Moving the InkWell must not cost the tile its only job.
    int taps = 0;
    await _pumpTile(tester, onTap: () => taps++);

    await tester.tap(find.byType(WallpaperTile));
    await tester.pump();

    expect(taps, 1);
  });
}
