import 'package:meta/meta.dart';
import 'package:tela/domain/models/purity.dart';

/// One file queued for a beam, already resolved to something readable.
///
/// **[path] is always a plain local file, never a `content:` document URI.**
/// A vault image's location is a SAF URI that only the native side can open,
/// so resolving it is the caller's job (`LocalPreviewCache.materialize`) and
/// is done before a [BeamFile] exists. Keeping that out of here is what lets
/// the whole beam be tested as plain Dart against a temp directory.
///
/// [purity] rides along because the gate is per-file, not per-batch: a
/// selection may mix safe and explicit wallpapers, and the explicit ones alone
/// are what an opt-in setting governs. Dropping it here would force the rule
/// to be re-derived from a filename downstream.
///
/// ```dart
/// BeamFile(
///   id: 'wallhaven-e7jvjd',
///   fileName: 'wallhaven-e7jvjd.jpg',
///   path: '/data/.../wallhaven-e7jvjd.jpg',
///   sizeBytes: 2215553,
///   mimeType: 'image/jpeg',
///   purity: Purity.sfw,
/// );
/// ```
@immutable
class BeamFile {
  /// Creates a queued file.
  const BeamFile({
    required this.id,
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.mimeType,
    required this.purity,
  });

  /// This file's id within one beam. Unique per send, not globally.
  final String id;

  /// The name the receiver should write it under.
  final String fileName;

  /// Where to read the bytes from — a plain local path. See the class doc.
  final String path;

  /// How many bytes the receiver should expect.
  final int sizeBytes;

  /// Its media type, for the receiver's own filing.
  final String mimeType;

  /// How explicit it is, so the beam gate can be applied per file.
  final Purity purity;

  @override
  bool operator ==(Object other) => other is BeamFile && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
