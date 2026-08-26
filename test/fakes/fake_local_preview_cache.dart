import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/vault_thumbnail.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// In-memory [LocalPreviewCache] modelling a download's three location schemes.
///
/// A `file:` location resolves to a non-temporary preview (the download's own
/// file, never tela's to delete); a MediaStore `content:` or SAF document URI
/// resolves to a temporary copy that must be released; anything `unreadable`
/// resolves to null, standing in for a file deleted behind tela's back so the
/// viewer falls back to Wallhaven.
///
/// The `bounds` constructor argument stands in for what the native side would
/// have decoded off a vault file's own header — a fixture location with no
/// entry there is an unreadable one, the same reading [materializeThumbnail]
/// gives a corrupt file on device.
class FakeLocalPreviewCache implements LocalPreviewCache {
  /// Creates a fake whose [unreadable] locations materialise to null.
  FakeLocalPreviewCache({
    Set<Uri> unreadable = const <Uri>{},
    Map<Uri, ({int width, int height})> bounds =
        const <Uri, ({int width, int height})>{},
  }) : _unreadable = unreadable,
       _bounds = bounds;

  final Set<Uri> _unreadable;
  final Map<Uri, ({int width, int height})> _bounds;

  /// Locations passed to [materialize], in order — proves local-first.
  final List<Uri> materialised = <Uri>[];

  /// URLs fetched through [materializeRemote], in order — proves a wallpaper
  /// with no local file is downloaded rather than silently skipped.
  final List<Uri> fetched = <Uri>[];

  /// Previews handed back to [release], in order — proves cleanup.
  final List<LocalPreview> released = <LocalPreview>[];

  /// Locations passed to [materializeThumbnail], in order — proves a grid
  /// tile asks at most once per location.
  final List<Uri> thumbnailsRequested = <Uri>[];

  @override
  Future<LocalPreview?> materialize(Uri location) async {
    materialised.add(location);
    if (_unreadable.contains(location)) return null;
    return LocalPreview(
      path: '/cache/preview-${location.hashCode}',
      isTemporary: location.scheme != 'file',
    );
  }

  @override
  Future<LocalPreview?> materializeRemote(Uri imageUrl) async {
    fetched.add(imageUrl);
    if (_unreadable.contains(imageUrl)) return null;
    // Always temporary: a fetched wallpaper is tela's own copy, never a file
    // the user downloaded, so it is always owed a release.
    return LocalPreview(
      path: '/cache/preview-${imageUrl.hashCode}',
      isTemporary: true,
    );
  }

  @override
  Future<void> release(LocalPreview preview) async {
    released.add(preview);
  }

  @override
  Future<VaultThumbnail?> materializeThumbnail(
    Uri location,
    int maxDimensionPx,
  ) async {
    thumbnailsRequested.add(location);
    if (_unreadable.contains(location)) return null;
    final ({int width, int height})? size = _bounds[location];
    if (size == null) return null;
    return VaultThumbnail(
      path: '/cache/thumb-${location.hashCode}',
      width: size.width,
      height: size.height,
    );
  }
}
