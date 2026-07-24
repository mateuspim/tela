import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/downloads/drift_download_history.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';

void main() {
  late TelaDatabase db;
  late DriftDownloadHistory history;
  late DateTime clock;

  setUp(() {
    db = TelaDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026);
    // A hand-cranked clock: two downloads in the same millisecond would order
    // arbitrarily, and this history is entirely about order.
    history = DriftDownloadHistory(
      db,
      now: () => clock = clock.add(const Duration(minutes: 1)),
    );
  });

  tearDown(() => db.close());

  group('DriftDownloadHistory', () {
    test('has no downloads before anything is recorded', () async {
      expect(await history.downloads(), isEmpty);
    });

    test('round-trips every field a re-apply needs', () async {
      final Wallpaper wallpaper = _wallpaper(
        'e7jvjd',
        colors: const <String>['#660000', '#abbcda'],
      );

      await history.record(
        wallpaper: wallpaper,
        tier: StorageTier.filesOutsideGallery,
        location: _location,
      );

      final DownloadRecord recorded = (await history.downloads()).single;
      expect(recorded.location, _location);
      expect(recorded.tier, StorageTier.filesOutsideGallery);
      expect(recorded.downloadedAt.toUtc(), DateTime.utc(2026, 1, 1, 0, 1));
      // The whole wallpaper, so the grid draws and the fallback re-fetch works
      // with no network in between.
      expect(recorded.wallpaper.fullImageUrl, wallpaper.fullImageUrl);
      expect(recorded.wallpaper.thumbOriginalUrl, wallpaper.thumbOriginalUrl);
      expect(recorded.wallpaper.resolution, const Resolution(1080, 2400));
      expect(recorded.wallpaper.fileSizeBytes, 1024);
      expect(recorded.wallpaper.purity, Purity.sfw);
      expect(recorded.wallpaper.category, Category.general);
      expect(recorded.wallpaper.colors, <String>['#660000', '#abbcda']);
    });

    test('lists the most recent download first', () async {
      await _record(history, _wallpaper('aaaaaa'));
      await _record(history, _wallpaper('bbbbbb'));

      expect(
        (await history.downloads())
            .map((DownloadRecord d) => d.wallpaper.id)
            .toList(),
        <String>['bbbbbb', 'aaaaaa'],
      );
    });

    test(
      're-downloading updates the row instead of stacking a second',
      () async {
        final Wallpaper wallpaper = _wallpaper('e7jvjd');

        // Two recordable tiers on purpose: a first write to appPrivate is now
        // refused outright, which would leave this proving nothing about the
        // second one replacing it.
        await history.record(
          wallpaper: wallpaper,
          tier: StorageTier.filesOutsideGallery,
          location: Uri.parse('file:///data/tela/old.jpg'),
        );
        await history.record(
          wallpaper: wallpaper,
          tier: StorageTier.sharedGallery,
          location: _location,
        );

        final DownloadRecord recorded = (await history.downloads()).single;
        expect(recorded.location, _location, reason: 'the newest file wins');
        expect(recorded.tier, StorageTier.sharedGallery);
      },
    );

    test('refuses to record an explicit download', () async {
      // The second door, behind DownloadWallpaper's own check: an explicit
      // wallpaper's home is the private library, and a row here would be an
      // ungated, backed-up index of it.
      await _record(history, _wallpaper('e7jvjd', purity: Purity.nsfw));

      expect(await history.downloads(), isEmpty);
    });

    test('refuses to record a download to the private tier', () async {
      // The second door again, this time on the destination rather than the
      // wallpaper: the private library is that tier's index, so a row here
      // would be the ungated copy of it. Purity does not come into it.
      await _record(
        history,
        _wallpaper('e7jvjd'),
        tier: StorageTier.appPrivate,
      );
      await _record(
        history,
        _wallpaper('7j1mzo', purity: Purity.sketchy),
        tier: StorageTier.appPrivate,
      );

      expect(await history.downloads(), isEmpty);
    });

    test('still records a safe download to the gallery', () async {
      await _record(history, _wallpaper('e7jvjd'));

      // The rule above must not have quietly emptied History altogether.
      expect(
        (await history.downloads()).single.tier,
        StorageTier.sharedGallery,
      );
    });

    test('drops an app-private row written before the rule existed', () async {
      await _record(history, _wallpaper('e7jvjd'));
      await _forceTier(db, 'e7jvjd', 'appPrivate');

      // The v5 migration purges these, but the filter is the door behind it —
      // a private download's thumbnail must not reach an ungated screen even
      // if a row somehow reaches this listing.
      expect(await history.downloads(), isEmpty);
    });

    test('drops a row whose purity no longer reads as safe', () async {
      await _record(history, _wallpaper('e7jvjd'));
      await _corruptPurity(db, 'e7jvjd');

      // A corrupt purity reads as nsfw by design. An explicit thumbnail must
      // not reach a screen with no FLAG_SECURE and no lock: withhold the row.
      expect(await history.downloads(), isEmpty);
    });

    test('reads a wallpaper stored with no colors as no colors', () async {
      await _record(history, _wallpaper('e7jvjd'));

      expect((await history.downloads()).single.wallpaper.colors, isEmpty);
    });

    test('forgets one row and leaves the others alone', () async {
      await _record(history, _wallpaper('e7jvjd'));
      await _record(history, _wallpaper('7j1mzo'));

      await history.forget(_ref('e7jvjd'));

      expect(
        (await history.downloads()).map((DownloadRecord d) => d.wallpaper.id),
        <String>['7j1mzo'],
      );
    });

    test('forgetting a row that is not there is not an error', () async {
      await _record(history, _wallpaper('e7jvjd'));

      await history.forget(_ref('nothere'));

      expect(await history.downloads(), hasLength(1));
    });
  });
}

final Uri _location = Uri.parse('content://media/external/images/media/42');

Future<void> _record(
  DriftDownloadHistory history,
  Wallpaper wallpaper, {
  StorageTier tier = StorageTier.sharedGallery,
}) {
  return history.record(wallpaper: wallpaper, tier: tier, location: _location);
}

/// Retiers a row behind the adapter's back, standing in for the rows written
/// before the destination rule existed.
Future<void> _forceTier(TelaDatabase db, String id, String tier) {
  return db.customStatement(
    'UPDATE downloaded_wallpapers SET tier = ? WHERE id = ?',
    <Object>[tier, id],
  );
}

/// Writes a purity no [Purity] has, the way a hand-edited or damaged row would.
Future<void> _corruptPurity(TelaDatabase db, String id) {
  return db.customStatement(
    'UPDATE downloaded_wallpapers SET purity = ? WHERE id = ?',
    <Object>['not-a-purity', id],
  );
}

Wallpaper _wallpaper(
  String id, {
  Purity purity = Purity.sfw,
  List<String> colors = const <String>[],
}) {
  return Wallpaper(
    id: id,
    source: SourceId.wallhaven,
    fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-$id.jpg',
    thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/$id.jpg',
    thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/$id.jpg',
    thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/$id.jpg',
    resolution: const Resolution(1080, 2400),
    fileSizeBytes: 1024,
    purity: purity,
    category: Category.general,
    colors: colors,
  );
}

WallpaperRef _ref(String id) => WallpaperRef(SourceId.wallhaven, id);
