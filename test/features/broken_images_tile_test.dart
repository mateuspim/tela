import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/broken_image_repair.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/stored_image.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/use_cases/repair_broken_images.dart';
import 'package:tela/features/settings/broken_images_tile.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';

void main() {
  final Uri vaultUri = Uri.parse('content://tree/vault/p1');

  testWidgets('says so when nothing is broken', (WidgetTester tester) async {
    await _pump(tester, FakeImageStore(), _FakeWallpaperStoring());

    await tester.tap(find.byKey(const Key('settings-broken-images')));
    await tester.pumpAndSettle();

    expect(find.text('No broken images found.'), findsOneWidget);
  });

  testWidgets('confirms, repairs, and reports the tally', (
    WidgetTester tester,
  ) async {
    final _FakeWallpaperStoring storing = _FakeWallpaperStoring();
    await _pump(tester, _storeWithEmpty(vaultUri), storing);

    await tester.tap(find.byKey(const Key('settings-broken-images')));
    await tester.pumpAndSettle();
    expect(find.text('1 broken image'), findsOneWidget);
    expect(find.textContaining('1 empty, 0 cut off'), findsOneWidget);

    await tester.tap(find.text('Repair'));
    await tester.pumpAndSettle();

    expect(storing.storedIds, <String>['p1']);
    expect(
      find.text("Repaired 1, deleted 0, couldn't fix 0."),
      findsOneWidget,
    );
  });

  testWidgets('cancelling touches nothing', (WidgetTester tester) async {
    final _FakeWallpaperStoring storing = _FakeWallpaperStoring();
    await _pump(tester, _storeWithEmpty(vaultUri), storing);

    await tester.tap(find.byKey(const Key('settings-broken-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(storing.storedIds, isEmpty);
  });
}

FakeImageStore _storeWithEmpty(Uri location) =>
    FakeImageStore(
        privateLibrary: <PrivateImage>[
          PrivateImage(
            ref: const WallpaperRef(SourceId.wallhaven, 'p1'),
            location: location,
            savedAt: DateTime(2026, 10, 6),
            sizeBytes: 0,
            tier: StorageTier.filesOutsideGallery,
          ),
        ],
      )
      ..conditions = <Uri, StoredImageCondition>{
        location: StoredImageCondition.empty,
      };

/// Stands in for `DownloadWallpaper`, recording which ids it stored.
class _FakeWallpaperStoring {
  final List<String> storedIds = <String>[];

  Future<StoredImage> store(
    Wallpaper wallpaper, {
    required StorageTier tier,
    TagFolder? tag,
  }) async {
    storedIds.add(wallpaper.id);
    return StoredImage(location: Uri.parse('content://x'), tier: tier);
  }
}

Future<Wallpaper> _fetch(WallpaperRef ref) async => Wallpaper(
  id: ref.id,
  source: ref.source,
  pageUrl: Uri.parse('https://wallhaven.cc/w/${ref.id}'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-${ref.id}.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/${ref.id}.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/${ref.id}.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/${ref.id}.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.nsfw,
  category: Category.general,
  colors: const <String>[],
);

Future<void> _pump(
  WidgetTester tester,
  FakeImageStore images,
  _FakeWallpaperStoring storing,
) async {
  final FakeDownloadHistory history = FakeDownloadHistory();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        imageStoreProvider.overrideWithValue(images),
        downloadHistoryProvider.overrideWithValue(history),
        repairBrokenImagesProvider.overrideWithValue(
          RepairBrokenImages(
            fetch: _fetch,
            store: storing.store,
            imageStore: images,
            history: history,
          ),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: BrokenImagesTile()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
