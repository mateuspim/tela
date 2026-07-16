import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Folder and database name of [thumbnailImageCache], under the temp directory.
const String thumbnailImageCacheKey = 'tela-thumbnails';

/// Folder and database name of [fullImageCache], under the temp directory.
const String fullImageCacheKey = 'tela-full-images';

/// `DefaultCacheManager`'s key — the one shared bucket everything used to fall
/// into, and the one that reached ~2GB.
///
/// Kept only so it can be **deleted**. Nothing reads or writes this bucket any
/// more, and that is exactly the problem: `flutter_cache_manager` evicts while
/// a bucket is being used, so a bucket nobody touches is a bucket that never
/// evicts. Left alone it would outlive the fix — an upgrading device would keep
/// every byte of the old cache for good, and a "Clear cache" tile that only
/// measured the new buckets would report 0 B while ~2GB sat next to it. Found
/// on the SM-X730, 2026-07-16: `files/libCachedImageData.db` was still there,
/// 2.5MB of rows, hours after the new buckets took over.
const String legacyImageCacheKey = 'libCachedImageData';

/// How many thumbnails to keep on disk.
///
/// A grid tile decodes `thumbOriginalUrl` at roughly 200dp — a few tens of KB
/// on the wire — so six hundred of them cost less than a handful of originals,
/// and re-fetching one spends a request from Wallhaven's 45/min. Keeping them
/// is the cheap choice.
const int thumbnailCacheObjectLimit = 600;

/// How long an unused thumbnail survives. Long: they are small and re-fetching
/// costs a request.
const Duration thumbnailCacheStalePeriod = Duration(days: 30);

/// How many full-resolution originals to keep on disk.
///
/// **This number is the whole fix.** `Config` can only cap a cache by *number
/// of objects*, never by bytes, so a bucket holding both kinds is capped by a
/// number that cannot tell a 40KB thumbnail from a 20MB 8K original — and one
/// shared 200-object bucket is exactly how the cache reached ~2GB on a tablet.
/// Splitting the buckets is what lets an object count mean a byte budget: ten
/// originals is ~100MB, and ~200MB against the largest sources Wallhaven
/// serves, because everything in this bucket is roughly one size.
///
/// Ten is a browsing window rather than a library: the viewer prefetches only
/// the immediate neighbour, so ten covers the image on screen and the ones
/// around it. Going further back re-fetches, which is the trade being made on
/// purpose — a wallpaper the user means to keep is downloaded, not cached.
const int fullImageCacheObjectLimit = 10;

/// How long an unused original survives. Short: it is the expensive thing here.
const Duration fullImageCacheStalePeriod = Duration(days: 3);

/// The disk cache for thumbnails: many, small, and worth keeping.
final CacheManager thumbnailImageCache = CacheManager(
  Config(
    thumbnailImageCacheKey,
    stalePeriod: thumbnailCacheStalePeriod,
    maxNrOfCacheObjects: thumbnailCacheObjectLimit,
  ),
);

/// The disk cache for full-resolution Wallhaven originals: few, huge, fleeting.
///
/// Kept apart from [thumbnailImageCache] for the reason spelled out on
/// [fullImageCacheObjectLimit]: a shared bucket cannot be capped meaningfully.
final CacheManager fullImageCache = CacheManager(
  Config(
    fullImageCacheKey,
    stalePeriod: fullImageCacheStalePeriod,
    maxNrOfCacheObjects: fullImageCacheObjectLimit,
  ),
);
