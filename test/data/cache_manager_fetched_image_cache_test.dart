import 'dart:io';

import 'package:file/file.dart' as file_api;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/images/cache_manager_fetched_image_cache.dart';

void main() {
  late Directory temp;
  late Directory support;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tela_image_cache');
    // flutter_cache_manager splits a bucket in two: the cached files live under
    // the temp directory, the sqflite index of them beside the app's own files.
    support = await Directory.systemTemp.createTemp('tela_image_support');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
    await support.delete(recursive: true);
  });

  test('adds up every bucket, so the tile can name a real figure', () async {
    _writeBytes('${temp.path}/thumbs/a.jpg', 400);
    _writeBytes('${temp.path}/full/b.jpg', 1600);
    final CacheManagerFetchedImageCache cache = _cache(temp, support);

    expect(await cache.sizeInBytes(), 2000);
  });

  test('counts files in nested folders', () async {
    // flutter_cache_manager shards its files, so a flat listing would report a
    // cache smaller than it is — and a "Clear cache (0 B)" tile is dead.
    _writeBytes('${temp.path}/thumbs/ab/cd/deep.jpg', 512);
    final CacheManagerFetchedImageCache cache = _cache(temp, support);

    expect(await cache.sizeInBytes(), 512);
  });

  test('an empty cache is zero, not an error', () async {
    // Nothing has been fetched yet: the folders do not exist at all.
    expect(await _cache(temp, support).sizeInBytes(), 0);
  });

  test('clearing empties every bucket', () async {
    final _FakeBucket thumbs = _FakeBucket();
    final _FakeBucket full = _FakeBucket();
    final CacheManagerFetchedImageCache cache = CacheManagerFetchedImageCache(
      buckets: <CacheManager>[thumbs, full],
      bucketKeys: const <String>['thumbs', 'full'],
      temporaryDirectory: () async => temp,
      supportDirectory: () async => support,
    );

    await cache.clear();

    expect(thumbs.emptied, isTrue);
    expect(full.emptied, isTrue, reason: 'both buckets, or the tile lies');
  });

  test('clearing takes files no store row points at', () async {
    // The bug the tablet found (2026-07-24): "Image cache cleared." toasted and
    // the tile stayed at 3.6 GB. `emptyCache()` only deletes what the store
    // still has rows for, and `sizeInBytes` counts every byte on disk — so an
    // orphan is reported forever and clears never. _FakeBucket stands in for a
    // store that knows about none of these files, which is the whole point.
    _writeBytes('${temp.path}/thumbs/orphan.jpg', 4000);
    _writeBytes('${temp.path}/full/ab/cd/orphan.jpg', 9000);
    final CacheManagerFetchedImageCache cache = _cacheWith(
      <CacheManager>[_FakeBucket(), _FakeBucket()],
      temp,
      support,
    );

    await cache.clear();

    expect(await cache.sizeInBytes(), 0, reason: 'a cleared cache is empty');
  });

  test(
    'clearing a bucket nothing was ever written to is not an error',
    () async {
      final CacheManagerFetchedImageCache cache = _cacheWith(
        <CacheManager>[_FakeBucket()],
        temp,
        support,
      );

      await cache.clear();

      expect(await cache.sizeInBytes(), 0);
    },
  );

  test('clearing leaves the legacy bucket gone too', () async {
    _writeBytes('${temp.path}/thumbs/orphan.jpg', 400);
    _writeBytes('${temp.path}/libCachedImageData/old.jpg', 5000);
    _writeBytes('${support.path}/libCachedImageData.db', 2500);
    final CacheManagerFetchedImageCache cache = _cacheWith(
      <CacheManager>[_FakeBucket()],
      temp,
      support,
    );

    await cache.clear();

    expect(Directory('${temp.path}/libCachedImageData').existsSync(), isFalse);
    expect(File('${support.path}/libCachedImageData.db').existsSync(), isFalse);
    expect(await cache.sizeInBytes(), 0);
  });

  group('the bucket an older tela left behind', () {
    // Nothing reads or writes libCachedImageData any more, so it never evicts:
    // whatever it grew to — ~2GB on the tablet — it keeps forever. Found on the
    // SM-X730, 2026-07-16, still holding its 2.5MB index hours after the split.
    test('counts toward the figure until it is purged', () async {
      _writeBytes('${temp.path}/libCachedImageData/old.jpg', 5000);
      _writeBytes('${support.path}/libCachedImageData.db', 2500);

      // A tile reporting only the new buckets would say "0 B" with all of that
      // sitting next to it.
      expect(await _cache(temp, support).sizeInBytes(), 7500);
    });

    test('is purged whole: the files and the index beside them', () async {
      _writeBytes('${temp.path}/libCachedImageData/old.jpg', 5000);
      _writeBytes('${support.path}/libCachedImageData.db', 2500);
      _writeBytes('${support.path}/libCachedImageData.db-journal', 100);

      await _cache(temp, support).purgeLegacyCache();

      expect(
        Directory('${temp.path}/libCachedImageData').existsSync(),
        isFalse,
      );
      // The index is stored apart from the files it indexes, so deleting the
      // folder alone leaves rows pointing at nothing.
      expect(File('${support.path}/libCachedImageData.db').existsSync(), false);
      expect(
        File('${support.path}/libCachedImageData.db-journal').existsSync(),
        isFalse,
      );
      expect(await _cache(temp, support).sizeInBytes(), 0);
    });

    test('purging never touches the live buckets', () async {
      _writeBytes('${temp.path}/thumbs/keep.jpg', 400);
      _writeBytes('${temp.path}/libCachedImageData/old.jpg', 5000);

      await _cache(temp, support).purgeLegacyCache();

      expect(await _cache(temp, support).sizeInBytes(), 400);
    });

    test('purging a device that never had one is not an error', () async {
      await _cache(temp, support).purgeLegacyCache();

      expect(await _cache(temp, support).sizeInBytes(), 0);
    });

    test('purging twice is not an error', () async {
      _writeBytes('${temp.path}/libCachedImageData/old.jpg', 5000);
      final CacheManagerFetchedImageCache cache = _cache(temp, support);

      await cache.purgeLegacyCache();
      await cache.purgeLegacyCache();

      expect(await cache.sizeInBytes(), 0);
    });
  });
}

CacheManagerFetchedImageCache _cache(Directory temp, Directory support) {
  return _cacheWith(const <CacheManager>[], temp, support);
}

CacheManagerFetchedImageCache _cacheWith(
  List<CacheManager> buckets,
  Directory temp,
  Directory support,
) {
  return CacheManagerFetchedImageCache(
    buckets: buckets,
    bucketKeys: const <String>['thumbs', 'full'],
    temporaryDirectory: () async => temp,
    supportDirectory: () async => support,
  );
}

void _writeBytes(String path, int length) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(List<int>.filled(length, 0));
}

/// [CacheManager] that records the one call this adapter makes of it.
class _FakeBucket extends CacheManager {
  _FakeBucket()
    : super(
        Config('fake-bucket', repo: _NoRepo(), fileSystem: _NoFileSystem()),
      );

  bool emptied = false;

  @override
  Future<void> emptyCache() async {
    emptied = true;
  }
}

/// Keeps [_FakeBucket]'s construction off the temp directory, which a real
/// `Config` reaches for through a platform channel no unit test has.
class _NoFileSystem implements FileSystem {
  @override
  Future<file_api.File> createFile(String name) => throw UnimplementedError();
}

/// Keeps [_FakeBucket]'s construction off sqflite.
class _NoRepo implements CacheInfoRepository {
  @override
  Future<bool> close() async => true;

  @override
  Future<int> delete(int id) async => 0;

  @override
  Future<int> deleteAll(Iterable<int> ids) async => 0;

  @override
  Future<void> deleteDataFile() async {}

  @override
  Future<bool> exists() async => false;

  @override
  Future<CacheObject?> get(String key) async => null;

  @override
  Future<List<CacheObject>> getAllObjects() async => <CacheObject>[];

  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async =>
      <CacheObject>[];

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async =>
      <CacheObject>[];

  @override
  Future<CacheObject> insert(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async => cacheObject;

  @override
  Future<bool> open() async => true;

  @override
  Future<int> update(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async => 0;

  @override
  Future<dynamic> updateOrInsert(CacheObject cacheObject) async => cacheObject;
}
