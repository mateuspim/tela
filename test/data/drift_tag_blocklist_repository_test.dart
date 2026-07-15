import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/db/tela_database.dart';
import 'package:tela/data/tag_blocklist/drift_tag_blocklist_repository.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

void main() {
  late TelaDatabase db;
  late DriftTagBlocklistRepository blocklist;
  late DateTime clock;

  setUp(() {
    db = TelaDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026);
    // A hand-cranked clock, so block order is pinned without sleeping between
    // writes — two blocks in the same millisecond would order arbitrarily.
    blocklist = DriftTagBlocklistRepository(
      db,
      now: () => clock = clock.add(const Duration(minutes: 1)),
    );
  });

  tearDown(() => db.close());

  group('DriftTagBlocklistRepository', () {
    test('has nothing blocked before anything is blocked', () async {
      expect(await blocklist.all(), isEmpty);
      expect(await blocklist.blockedNames(), isEmpty);
    });

    test('blocks a tag by id and name', () async {
      await blocklist.block(const WallpaperTag(id: 37, name: 'nature'));

      expect(await blocklist.all(), <WallpaperTag>[
        const WallpaperTag(id: 37, name: 'nature'),
      ]);
      expect(await blocklist.blockedNames(), <String>{'nature'});
    });

    test('lists the most recently blocked tag first', () async {
      await blocklist.block(const WallpaperTag(id: 1, name: 'older'));
      await blocklist.block(const WallpaperTag(id: 2, name: 'newer'));

      final List<WallpaperTag> loaded = await blocklist.all();

      expect(loaded.map((WallpaperTag t) => t.id), <int>[2, 1]);
    });

    test('blocking the same id twice overwrites, not appends', () async {
      await blocklist.block(const WallpaperTag(id: 37, name: 'nature'));
      await blocklist.block(const WallpaperTag(id: 37, name: 'renamed'));

      final List<WallpaperTag> loaded = await blocklist.all();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'renamed');
    });

    test('unblocks a blocked tag', () async {
      await blocklist.block(const WallpaperTag(id: 37, name: 'nature'));

      await blocklist.unblock(37);

      expect(await blocklist.all(), isEmpty);
      expect(await blocklist.blockedNames(), isEmpty);
    });

    test('unblocking a tag that was never blocked is a no-op', () async {
      await blocklist.unblock(404);

      expect(await blocklist.all(), isEmpty);
    });
  });
}
