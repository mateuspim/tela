import 'package:tela/domain/ports/fetched_image_cache.dart';

/// [FetchedImageCache] holding a made-up figure, with no disk behind it.
class FakeFetchedImageCache implements FetchedImageCache {
  /// Creates a cache reporting [bytes] until it is cleared.
  FakeFetchedImageCache({int bytes = 0}) : _bytes = bytes;

  int _bytes;

  /// Whether [clear] was called.
  bool cleared = false;

  /// Whether [purgeLegacyCache] was called.
  bool purgedLegacy = false;

  @override
  Future<int> sizeInBytes() async => _bytes;

  /// Empties, and answers honestly afterwards — a fake that kept reporting the
  /// old figure would hide a tile that never re-reads it.
  @override
  Future<void> clear() async {
    cleared = true;
    _bytes = 0;
  }

  @override
  Future<void> purgeLegacyCache() async {
    purgedLegacy = true;
  }
}
