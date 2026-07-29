import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';

import '../fakes/fake_download_history.dart';
import '../fakes/fake_image_store.dart';

void main() {
  /// The probe that marks a history row whose file went away behind tela's
  /// back, and the cost of asking.
  group('missingDownloadsProvider', () {
    test('names exactly the rows whose file will not open', () async {
      final Uri gone = Uri.parse('file:///b.jpg');
      final ProviderContainer container = await _containerOf(
        ids: <String>['a', 'b', 'c'],
        unreadable: <Uri>{gone},
      );

      expect(
        await container.read(missingDownloadsProvider.future),
        <String>{'wallhaven-b'},
      );
    });

    // The whole reason `canReadAll` exists. A `Future.wait` over `canRead`
    // looked concurrent and was not — every call queued on one native thread,
    // so a history of hundreds paid hundreds of round trips and the badges
    // took long enough to arrive that the screen looked broken (owner,
    // 2026-07-28). Counting the crossings is the only way to catch a
    // regression to a per-row loop, since both shapes give the same answer.
    test('probes a whole history in one crossing', () async {
      final FakeImageStore images = FakeImageStore();
      final ProviderContainer container = await _containerOf(
        ids: <String>['a', 'b', 'c', 'd', 'e'],
        images: images,
      );

      await container.read(missingDownloadsProvider.future);

      expect(images.canReadAllCalls, 1);
    });

    test('an empty history reports nothing missing', () async {
      final ProviderContainer container = await _containerOf(
        ids: const <String>[],
      );

      expect(await container.read(missingDownloadsProvider.future), isEmpty);
    });
  });
}

/// A container whose history holds one safe download per id in [ids].
Future<ProviderContainer> _containerOf({
  required List<String> ids,
  Set<Uri> unreadable = const <Uri>{},
  FakeImageStore? images,
}) async {
  final FakeDownloadHistory history = FakeDownloadHistory();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      downloadHistoryProvider.overrideWithValue(history),
      imageStoreProvider.overrideWithValue(
        images ?? FakeImageStore(unreadable: unreadable),
      ),
    ],
  );
  addTearDown(container.dispose);
  for (final String id in ids) {
    await history.record(
      wallpaper: _wallpaper(id),
      tier: StorageTier.filesOutsideGallery,
      location: Uri.parse('file:///$id.jpg'),
    );
  }
  return container;
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1080, 2400),
  fileSizeBytes: 1024,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
