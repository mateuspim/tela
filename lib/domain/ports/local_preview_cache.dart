import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/vault_thumbnail.dart';

/// Materialises a downloaded image into a file Flutter can decode offline.
///
/// A download's location can be a `file:` URI, a MediaStore `content:` URI, or
/// a SAF document URI, and `FileImage` reads only the first. This port hides
/// that difference behind one call: it returns a readable local [LocalPreview]
/// for any of the three, copying the content URIs into a throwaway cache file
/// and pointing straight at the original for a plain `file:` one.
///
/// Implementations must never log the URI or the resolved path — the same rule
/// that keeps stored paths out of every other log in tela.
abstract interface class LocalPreviewCache {
  /// Returns a readable local copy of the image at [location], or null.
  ///
  /// Answers null for every reason the source cannot be read — deleted,
  /// revoked, unreadable — so the caller can fall back to the network source
  /// exactly as `ApplyDownload` does. It never throws for a missing file: a
  /// download the user deleted is an ordinary state of the world.
  Future<LocalPreview?> materialize(Uri location);

  /// Deletes a throwaway preview; a no-op for a non-temporary one.
  ///
  /// Releasing a [LocalPreview] whose `isTemporary` is false must do nothing —
  /// that path is the download's own file, not tela's to delete.
  Future<void> release(LocalPreview preview);

  /// Decodes a downsampled [VaultThumbnail] for [location], or null.
  ///
  /// A grid tile for a vault (SAF) image cannot use [materialize]: that copies
  /// the whole original file, which is the right cost once for a single
  /// full-screen viewer but far too much paid per tile for a wall of dozens of
  /// them scrolling past. This decodes at roughly [maxDimensionPx] instead, and
  /// the native side caches the result by [location] so a tile scrolled past
  /// and back costs no second decode — there is deliberately no matching
  /// release: unlike [materialize]'s throwaway copy, this lives in the
  /// platform's own cache directory for as long as the OS keeps it.
  ///
  /// Answers null for every reason the source cannot be read, the same as
  /// [materialize].
  Future<VaultThumbnail?> materializeThumbnail(
    Uri location,
    int maxDimensionPx,
  );
}
