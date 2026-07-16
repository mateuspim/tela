import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/downloads/download_immersive_session.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';
import '../fakes/fake_immersive_system_ui.dart';
import '../fakes/fake_local_preview_cache.dart';
import '../fakes/fake_wallpaper_applier.dart';

void main() {
  testWidgets('shows the saved local file first, before any network', (
    WidgetTester tester,
  ) async {
    final FakeLocalPreviewCache cache = FakeLocalPreviewCache();
    await _pump(
      tester,
      _session(<DownloadRecord>[_download('e7jvjd')]),
      cache: cache,
    );

    // The viewer asked the port to materialise the download's own location
    // before it ever reached for Wallhaven — that is what makes History work
    // offline.
    expect(cache.materialised, <Uri>[_locationOf('e7jvjd')]);
  });

  testWidgets(
    'falls back to Wallhaven and stays badged when the file is gone',
    (
      WidgetTester tester,
    ) async {
      final Uri gone = _locationOf('7j1mzo');
      await _pump(
        tester,
        _session(<DownloadRecord>[_download('7j1mzo')]),
        // The missing badge is derived from the history listing crossed with
        // the file probe, so the row must be in the history the provider reads.
        history: FakeDownloadHistory(
          initial: <DownloadRecord>[_download('7j1mzo')],
        ),
        cache: FakeLocalPreviewCache(unreadable: <Uri>{gone}),
        imageStore: FakeImageStore(unreadable: <Uri>{gone}),
      );
      await tester.pumpAndSettle();

      // The missing state is obvious in the viewer, mirroring the grid's badge.
      expect(find.text('Not on this device'), findsOneWidget);
    },
  );

  testWidgets('Set chooses a target and applies the shown download', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    await _pump(
      tester,
      _session(<DownloadRecord>[_download('e7jvjd')]),
      applier: applier,
    );

    await tester.tap(find.byKey(const Key('download-viewer-set')));
    await tester.pumpAndSettle();
    expect(find.text('Set wallpaper on'), findsOneWidget);
    await tester.tap(find.text('Home and lock screens'));
    await tester.pumpAndSettle();

    expect(applier.receivedSources, <Uri>[_locationOf('e7jvjd')]);
    expect(applier.receivedTarget, WallpaperTarget.both);
    expect(find.text('Wallpaper set.'), findsOneWidget);
  });

  testWidgets('Set and forget follow the item shown after Next', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    // Newest first: index 0 is 'newer', index 1 is 'older'.
    await _pump(
      tester,
      _session(<DownloadRecord>[_download('newer'), _download('older')]),
      applier: applier,
    );

    await tester.tap(find.byKey(const Key('immersive-viewer-next')));
    await tester.pumpAndSettle();

    // The position moved, and the action now belongs to the second item.
    expect(find.bySemanticsLabel('2 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('download-viewer-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home and lock screens'));
    await tester.pumpAndSettle();

    expect(applier.receivedSources, <Uri>[_locationOf('older')]);
  });

  testWidgets('overflow forgets the shown row, and says the file stays', (
    WidgetTester tester,
  ) async {
    final FakeDownloadHistory history = FakeDownloadHistory(
      initial: <DownloadRecord>[_download('e7jvjd')],
    );
    await _pump(
      tester,
      _session(<DownloadRecord>[_download('e7jvjd')]),
      history: history,
    );

    await tester.tap(find.byKey(const Key('download-viewer-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from history'));
    await tester.pumpAndSettle();

    // The wording is the feature: it must say the wallpaper file survives.
    expect(find.text('Remove from history?'), findsOneWidget);
    expect(
      find.textContaining('The wallpaper file stays where it was downloaded'),
      findsOneWidget,
    );
    // Not forgotten until confirmed.
    expect(history.recorded, hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(history.recorded, isEmpty);
    // And it leaves: the row it was showing is gone. This exit rides the same
    // PopScope -> _exitFullscreen -> onClose path as the close button, so it
    // was dead for the same reason until onClose stopped calling maybePop().
    expect(find.byType(DownloadImmersiveSession), findsNothing);
    expect(find.text('grid'), findsOneWidget);
  });

  testWidgets('releases every temporary preview it materialised', (
    WidgetTester tester,
  ) async {
    final FakeLocalPreviewCache cache = FakeLocalPreviewCache();
    await _pump(
      tester,
      _session(<DownloadRecord>[_download('newer'), _download('older')]),
      cache: cache,
    );

    await tester.tap(find.byKey(const Key('immersive-viewer-next')));
    await tester.pumpAndSettle();
    // Leaving the first record behind released its throwaway copy.
    expect(cache.released, isNotEmpty);
  });

  // The close button did nothing on the tablet: onClose called maybePop(),
  // which consulted the viewer's own PopScope before its canPop rebuild had
  // landed, so the exit re-entered itself and the route stayed put. Back
  // worked, which is what hid it. The private viewer pins the same path.
  testWidgets('the close button pops the viewer back to the grid', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _session(<DownloadRecord>[_download('e7jvjd')]));
    expect(find.byType(DownloadImmersiveSession), findsOneWidget);

    await tester.tap(find.byKey(const Key('immersive-viewer-close')));
    await tester.pumpAndSettle();

    expect(find.byType(DownloadImmersiveSession), findsNothing);
    expect(find.text('grid'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  GallerySessionController<DownloadRecord> session, {
  FakeWallpaperApplier? applier,
  FakeDownloadHistory? history,
  FakeImageStore? imageStore,
  FakeLocalPreviewCache? cache,
}) async {
  addTearDown(session.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallpaperApplierProvider.overrideWithValue(
          applier ?? FakeWallpaperApplier(),
        ),
        downloadHistoryProvider.overrideWithValue(
          history ?? FakeDownloadHistory(),
        ),
        imageStoreProvider.overrideWithValue(imageStore ?? FakeImageStore()),
        localPreviewCacheProvider.overrideWithValue(
          cache ?? FakeLocalPreviewCache(),
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
        // The viewer is pushed over a history-grid stand-in, as in the app, so
        // its close path has somewhere to pop back to.
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DownloadImmersiveSession(
                      session: session,
                      systemUi: FakeImmersiveSystemUi(),
                    ),
                  ),
                ),
                child: const Text('grid'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('grid'));
  await tester.pumpAndSettle();
}

GallerySessionController<DownloadRecord> _session(
  List<DownloadRecord> records, {
  int initialIndex = 0,
}) {
  return GallerySessionController<DownloadRecord>(
    identity: 'download-history',
    items: records,
    initialIndex: initialIndex,
    itemKey: (DownloadRecord record) => record.wallpaper.id,
  );
}

Uri _locationOf(String id) =>
    Uri.parse('content://media/external/images/media/$id');

DownloadRecord _download(String id) => DownloadRecord(
  wallpaper: Wallpaper(
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
  ),
  tier: StorageTier.sharedGallery,
  location: _locationOf(id),
  downloadedAt: DateTime(2026, 7, 14),
);
