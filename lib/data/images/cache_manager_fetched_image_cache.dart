import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';
import 'package:tela/domain/ports/fetched_image_cache.dart';

/// [FetchedImageCache] over the project's own `flutter_cache_manager` buckets.
///
/// ```dart
/// final FetchedImageCache cache = CacheManagerFetchedImageCache();
/// ```
class CacheManagerFetchedImageCache implements FetchedImageCache {
  /// Creates the adapter over the app's thumbnail and full-image buckets.
  ///
  /// The buckets and the two directories are injectable so a test can measure
  /// real folders without a real Wallhaven or a real device.
  CacheManagerFetchedImageCache({
    List<CacheManager>? buckets,
    List<String>? bucketKeys,
    Future<Directory> Function()? temporaryDirectory,
    Future<Directory> Function()? supportDirectory,
  }) : _buckets =
           buckets ?? <CacheManager>[thumbnailImageCache, fullImageCache],
       _bucketKeys =
           bucketKeys ??
           const <String>[thumbnailImageCacheKey, fullImageCacheKey],
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final List<CacheManager> _buckets;
  final List<String> _bucketKeys;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<Directory> Function() _supportDirectory;

  /// Adds up the files themselves, the live buckets and the abandoned one.
  ///
  /// `CacheManager` keeps no byte total — it counts objects, which is the whole
  /// reason the buckets are split — so the only honest answer comes from
  /// `stat`ing the folders it writes into. The legacy bucket counts too: until
  /// [purgeLegacyCache] has run it is real disk the user is paying for, and a
  /// tile reporting 0 B beside 2GB of it would simply be lying.
  @override
  Future<int> sizeInBytes() async {
    final Directory temp = await _temporaryDirectory();
    int total = 0;
    for (final String key in <String>[..._bucketKeys, legacyImageCacheKey]) {
      total += await _folderBytes(Directory('${temp.path}/$key'));
    }
    return total + await _legacyDatabaseBytes();
  }

  /// Zero for a bucket nothing has been written to yet — an absent folder is
  /// an empty cache, not an error.
  Future<int> _folderBytes(Directory folder) async {
    if (!folder.existsSync()) return 0;
    int total = 0;
    await for (final FileSystemEntity entity in folder.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Empties the buckets' indexes **and** deletes the folders under them.
  ///
  /// `emptyCache()` alone is not a clear: it walks the store's rows and deletes
  /// the file each one points at, so a file whose row was evicted or lost is
  /// invisible to it — and fully visible to [sizeInBytes], which `stat`s the
  /// folder. Orphans therefore accumulate, get reported, and cannot be cleared:
  /// the tablet sat at **3.6 GB before and after** a "cleared" toast
  /// (2026-07-24), against a 600-thumbnail + 10-original budget. Same shape as
  /// the legacy bucket — a bucket nobody's store tracks is a bucket that never
  /// shrinks.
  ///
  /// Order is load-bearing: rows first, through the live sqflite connection,
  /// then the folder. `IOFileSystem.createFile` re-creates a missing bucket
  /// directory on the next write, so deleting it costs nothing but the bytes.
  @override
  Future<void> clear() async {
    for (final CacheManager bucket in _buckets) {
      await bucket.emptyCache();
    }
    final Directory temp = await _temporaryDirectory();
    for (final String key in _bucketKeys) {
      final Directory folder = Directory('${temp.path}/$key');
      if (folder.existsSync()) await folder.delete(recursive: true);
    }
    await purgeLegacyCache();
  }

  /// Deletes the old bucket's files *and* its metadata database.
  ///
  /// Both halves, because `flutter_cache_manager` splits them: the cached files
  /// live under the temp directory, and the sqflite index of them lives beside
  /// the app's own files as `<key>.db`. Deleting only the folder would leave
  /// the index behind — 2.5MB of rows pointing at files that no longer exist,
  /// which is what the tablet was still carrying.
  @override
  Future<void> purgeLegacyCache() async {
    final Directory temp = await _temporaryDirectory();
    final Directory folder = Directory('${temp.path}/$legacyImageCacheKey');
    if (folder.existsSync()) await folder.delete(recursive: true);
    for (final File file in await _legacyDatabaseFiles()) {
      if (file.existsSync()) await file.delete();
    }
  }

  Future<int> _legacyDatabaseBytes() async {
    int total = 0;
    for (final File file in await _legacyDatabaseFiles()) {
      if (file.existsSync()) total += await file.length();
    }
    return total;
  }

  /// The database and the journal sqflite leaves next to it.
  Future<List<File>> _legacyDatabaseFiles() async {
    final Directory support = await _supportDirectory();
    final String base = '${support.path}/$legacyImageCacheKey.db';
    return <File>[File(base), File('$base-journal')];
  }
}
