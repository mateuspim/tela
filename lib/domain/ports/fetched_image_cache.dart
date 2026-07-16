/// The disk cache of images fetched from Wallhaven, as Settings can act on it.
///
/// Not to be confused with `ImageStore`, which is the opposite thing: that
/// holds wallpapers the user chose to **keep**, in one of the three tiers, and
/// deleting from it loses something. Everything here is a copy of a file
/// Wallhaven still has, so clearing it costs only the time to fetch it again.
/// That is what makes an unprompted "Clear cache" button safe to offer.
///
/// ```dart
/// final int bytes = await cache.sizeInBytes();
/// await cache.clear();
/// ```
abstract interface class FetchedImageCache {
  /// Total bytes currently held on disk, across every bucket.
  ///
  /// The real figure, measured from the files themselves — a "Clear cache"
  /// tile that cannot say how much it would free is a tile nobody presses.
  /// Includes anything a previous version of tela left behind, because that is
  /// bytes the user is paying for whether or not this version put them there.
  /// Returns zero when nothing has been cached yet.
  Future<int> sizeInBytes();

  /// Empties every bucket. Never touches downloaded or private files.
  Future<void> clear();

  /// Deletes what an older tela cached, once, at startup.
  ///
  /// Before the buckets were split there was one cache, capped at 200 objects
  /// of any size, and on a tablet it reached ~2GB. Nothing reads that bucket
  /// now — which is precisely why it must be deleted rather than left to
  /// shrink: `flutter_cache_manager` only evicts a bucket while it is in use,
  /// so an abandoned one is frozen at its worst size forever. This is the same
  /// argument as the database's v5 purge: a new rule does not clean up what the
  /// old rule wrote.
  ///
  /// A no-op once it has run, and on a device that never had the old cache.
  Future<void> purgeLegacyCache();
}
