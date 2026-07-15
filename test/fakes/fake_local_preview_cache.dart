import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// In-memory [LocalPreviewCache] modelling a download's three location schemes.
///
/// A `file:` location resolves to a non-temporary preview (the download's own
/// file, never tela's to delete); a MediaStore `content:` or SAF document URI
/// resolves to a temporary copy that must be released; anything `unreadable`
/// resolves to null, standing in for a file deleted behind tela's back so the
/// viewer falls back to Wallhaven.
class FakeLocalPreviewCache implements LocalPreviewCache {
  /// Creates a fake whose [unreadable] locations materialise to null.
  FakeLocalPreviewCache({Set<Uri> unreadable = const <Uri>{}})
    : _unreadable = unreadable;

  final Set<Uri> _unreadable;

  /// Locations passed to [materialize], in order — proves local-first.
  final List<Uri> materialised = <Uri>[];

  /// Previews handed back to [release], in order — proves cleanup.
  final List<LocalPreview> released = <LocalPreview>[];

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
  Future<void> release(LocalPreview preview) async {
    released.add(preview);
  }
}
