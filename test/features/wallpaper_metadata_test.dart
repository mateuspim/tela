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
}

Future<void> _pumpMetadata(
  WidgetTester tester, {
  required ValueChanged<WallpaperLink> onFollow,
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
            details: _details(),
            onFollow: onFollow,
            onBlockTag: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

WallpaperDetails _details() => const WallpaperDetails(
  wallpaper: Wallpaper(
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
  tags: <WallpaperTag>[WallpaperTag(id: 101, name: 'landscape')],
  uploader: WallpaperUploader(
    username: 'tela-fixture',
    group: 'User',
    avatarUrl: 'https://example.com/avatar.jpg',
  ),
  source: 'https://example.com/source',
  views: 4523,
  favorites: 128,
);
