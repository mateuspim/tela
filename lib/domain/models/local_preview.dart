import 'package:meta/meta.dart';

/// A local file tela can hand to Flutter's image decoder for a download.
///
/// A `DownloadRecord`'s location may be a `file:` URI, a MediaStore `content:`
/// URI, or a Storage Access Framework document URI. Only the first is readable
/// by `FileImage`; the other two must be copied to a real file first. This is
/// the result of that copy — [isTemporary] says whether it is tela's throwaway
/// copy (which must be released) or the original file itself (which must not be
/// touched).
///
/// ```dart
/// final LocalPreview? preview = await cache.materialize(record.location);
/// if (preview != null) Image.file(File(preview.path));
/// ```
@immutable
class LocalPreview {
  /// Creates a preview pointing at a readable local [path].
  const LocalPreview({required this.path, required this.isTemporary});

  /// An absolute filesystem path a `FileImage` can decode.
  final String path;

  /// Whether [path] is a throwaway copy tela made and must delete on release.
  ///
  /// False when [path] is the download's own `file:` location: releasing it
  /// would delete the wallpaper the user downloaded, which is never tela's to
  /// do — the same rule that keeps "remove from history" from deleting a file.
  final bool isTemporary;

  @override
  bool operator ==(Object other) =>
      other is LocalPreview &&
      other.path == path &&
      other.isTemporary == isTemporary;

  @override
  int get hashCode => Object.hash(path, isTemporary);

  /// Names the preview without naming its path, per the no-paths-in-logs rule.
  @override
  String toString() => 'LocalPreview(temporary: $isTemporary)';
}
