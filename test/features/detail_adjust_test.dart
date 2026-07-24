import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_adjust_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/features/detail/crop_wallpaper_screen.dart';
import 'package:tela/features/detail/wallpaper_detail_screen.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_favorites_repository.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_system_wallpaper_editor.dart';
import '../fakes/fake_tag_blocklist_repository.dart';
import '../fakes/fake_wallpaper_sharer.dart';
import '../fakes/fake_wallpaper_source.dart';

void main() {
  testWidgets('a safe wallpaper offers the editor', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    expect(find.byKey(const Key('detail-adjust')), findsOneWidget);
  });

  testWidgets('a sketchy wallpaper offers it too', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester, purity: Purity.sketchy);

    expect(find.byKey(const Key('detail-adjust')), findsOneWidget);
  });

  testWidgets('an explicit wallpaper adjusts in the cropper, not the OEM', (
    WidgetTester tester,
  ) async {
    // The OEM editor is a separate app with its own wallpaper history, so
    // explicit pixels may not reach it — the same rule as the image share. But
    // tela's own cropper keeps them in-process, so the button now shows and
    // routes there instead of being withheld.
    final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor();
    await _pumpDetail(tester, purity: Purity.nsfw, editor: editor);

    expect(find.byKey(const Key('detail-adjust')), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-adjust')));
    await tester.pumpAndSettle();

    expect(find.byType(CropWallpaperScreen), findsOneWidget);
    expect(editor.opened, isEmpty);
  });

  testWidgets('tapping a safe one hands the full image to the OEM editor', (
    WidgetTester tester,
  ) async {
    final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor();
    await _pumpDetail(tester, editor: editor);

    await tester.tap(find.byKey(const Key('detail-adjust')));
    await tester.pumpAndSettle();

    expect(editor.opened, hasLength(1));
    expect(
      editor.opened.single.source,
      Uri.parse('https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg'),
    );
    expect(find.byType(CropWallpaperScreen), findsNothing);
  });

  testWidgets('a successful hand-off says nothing', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(tester);

    await tester.tap(find.byKey(const Key('detail-adjust')));
    await tester.pumpAndSettle();

    // tela never learns what the user did in the editor, so it has no outcome
    // to report. A "wallpaper set" snackbar here would be a lie: the user may
    // still be framing it, or may have backed out.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a device with no OEM editor falls back to the cropper', (
    WidgetTester tester,
  ) async {
    final FakeSystemWallpaperEditor editor = FakeSystemWallpaperEditor(
      failure: const WallpaperAdjustFailure(
        WallpaperAdjustProblem.unavailable,
      ),
    );
    await _pumpDetail(tester, editor: editor);

    await tester.tap(find.byKey(const Key('detail-adjust')));
    await tester.pumpAndSettle();

    // It tried the OEM editor, then opened tela's own rather than dead-ending.
    expect(editor.opened, hasLength(1));
    expect(find.byType(CropWallpaperScreen), findsOneWidget);
  });

  testWidgets('any other failure reads as a failure to open', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      editor: FakeSystemWallpaperEditor(
        failure: const WallpaperAdjustFailure(WallpaperAdjustProblem.source),
      ),
    );

    await tester.tap(find.byKey(const Key('detail-adjust')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open the wallpaper editor."), findsOneWidget);
  });
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  Purity purity = Purity.sfw,
  FakeSystemWallpaperEditor? editor,
}) async {
  final WallpaperDetails details = _details(purity: purity);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallhavenSourceProvider.overrideWithValue(
          FakeWallpaperSource(
            details: details,
          ),
        ),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
        downloadHistoryProvider.overrideWithValue(FakeDownloadHistory()),
        wallpaperSharerProvider.overrideWithValue(FakeWallpaperSharer()),
        tagBlocklistRepositoryProvider.overrideWithValue(
          FakeTagBlocklistRepository(),
        ),
        // Unbound, the adjust button reaches the real method channel.
        systemWallpaperEditorProvider.overrideWithValue(
          editor ?? FakeSystemWallpaperEditor(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WallpaperDetailScreen(
          wallpaper: details.wallpaper,
          immersiveSystemUi: FakeImmersiveSystemUi(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

WallpaperDetails _details({Purity purity = Purity.sfw}) {
  final Wallpaper wallpaper = Wallpaper(
    id: 'e7jvjd',
    source: SourceId.wallhaven,
    pageUrl: Uri.parse('https://wallhaven.cc/w/e7jvjd'),
    fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
    resolution: const Resolution(3840, 2160),
    fileSizeBytes: 1048576,
    purity: purity,
    category: Category.general,
    colors: const <String>['#660000'],
  );
  return WallpaperDetails(
    wallpaper: wallpaper,
    ratio: '1.78',
    fileType: 'image/jpeg',
    tags: const <WallpaperTag>[WallpaperTag(id: 101, name: 'landscape')],
    uploader: const WallpaperUploader(
      username: 'someone',
      group: 'User',
      avatarUrl: 'https://wallhaven.cc/avatar/someone.png',
    ),
    source: '',
    views: 1,
    favorites: 1,
  );
}
