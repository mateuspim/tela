import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/network/wallpaper_image_caches.dart';

/// The ~2GB on the tablet was one shared 200-object bucket holding 40KB
/// thumbnails and 20MB originals against a cap that could not tell them apart.
/// `Config` caps objects and never bytes, so an object count can only mean a
/// byte budget if everything in a bucket is roughly one size. These pin the
/// numbers that make that true.
///
/// The managers themselves are not built here: constructing a real `Config`
/// reaches for the temp directory through a platform channel. The numbers are
/// the decision; the `CacheManager` is plumbing over them.
void main() {
  test('thumbnails and full images do not share a bucket', () {
    expect(thumbnailImageCacheKey, isNot(fullImageCacheKey));
  });

  test('neither bucket is the shared default that caused this', () {
    // DefaultCacheManager's key: what every CachedNetworkImage falls back to
    // when no manager is named, which is where the 2GB accumulated.
    for (final String key in <String>[
      thumbnailImageCacheKey,
      fullImageCacheKey,
    ]) {
      expect(key, isNot('libCachedImageData'));
    }
  });

  test('the full-image bucket is a browsing window, not a library', () {
    // Ten originals at 5-20MB is ~100-200MB. Two hundred of them — the package
    // default this replaces — is the ~2GB that was measured.
    expect(fullImageCacheObjectLimit, lessThanOrEqualTo(16));
    expect(
      fullImageCacheStalePeriod,
      lessThanOrEqualTo(const Duration(days: 7)),
    );
  });

  test('the thumbnail bucket keeps plenty, for a long time', () {
    // Tens of KB each, and re-fetching one spends a request from the 45/min
    // budget: keeping them is the cheap choice.
    expect(thumbnailCacheObjectLimit, greaterThanOrEqualTo(200));
    expect(
      thumbnailCacheStalePeriod,
      greaterThanOrEqualTo(const Duration(days: 30)),
    );
  });

  test('a full image is budgeted far more tightly than a thumbnail', () {
    // The relationship is the invariant, not either number: whatever they are
    // tuned to, an original must never be as cheap to keep as a thumbnail.
    expect(fullImageCacheObjectLimit, lessThan(thumbnailCacheObjectLimit));
    expect(fullImageCacheStalePeriod, lessThan(thumbnailCacheStalePeriod));
  });
}
