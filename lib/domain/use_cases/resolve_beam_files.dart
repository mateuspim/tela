import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/ports/local_preview_cache.dart';

/// Turns stored images into files a beam can actually read.
///
/// **The vault is why this exists.** An app-private image's `location` is a
/// plain `file:` path any Dart code can open, but a vault image's is a
/// `content:` SAF document URI that only the platform can — and
/// `File.fromUri` throws synchronously on one, which is exactly the bug that
/// turned every vault tile into a grey box (see the private-library fix,
/// 2026-08-26). So a beam resolves through [LocalPreviewCache.materialize]
/// first, and only a resolved local path ever reaches [BeamFile].
///
/// Returns the files that could be resolved plus the previews to release once
/// the beam is done. **The caller owes that release**: `materialize` makes a
/// throwaway full-size copy for a SAF source, and a batch of forty left
/// unreleased is forty duplicated wallpapers in the cache directory.
///
/// ```dart
/// final resolved = await resolveBeamFiles(images);
/// try { await beam(files: resolved.files); }
/// finally { await resolved.release(); }
/// ```
class ResolveBeamFiles {
  /// Creates the use case. Every collaborator is injected (CLAUDE.md).
  const ResolveBeamFiles(this._previews);

  final LocalPreviewCache _previews;

  /// Resolves [images], skipping any that cannot be read.
  ///
  /// A file that will not materialize is dropped rather than failing the
  /// batch: one unreadable image out of forty should cost itself, not the
  /// other thirty-nine, and the sheet reports how many are actually going.
  Future<ResolvedBeamFiles> call(List<PrivateImage> images) async {
    final List<BeamFile> files = <BeamFile>[];
    final List<LocalPreview> temporary = <LocalPreview>[];
    for (final PrivateImage image in images) {
      final LocalPreview? preview = await _previews.materialize(image.location);
      if (preview == null) continue;
      if (preview.isTemporary) temporary.add(preview);
      files.add(_fileFor(image, preview));
    }
    return ResolvedBeamFiles(
      files: files,
      previews: _previews,
      temporary: temporary,
    );
  }

  BeamFile _fileFor(PrivateImage image, LocalPreview preview) {
    final String name = preview.path.split('/').last;
    return BeamFile(
      id: '${image.ref.source.value}-${image.ref.id}',
      fileName: name,
      path: preview.path,
      sizeBytes: image.sizeBytes,
      // The private library is explicit by definition — it is where NSFW
      // downloads land — so this is what makes the beam gate apply to it. A
      // safe image reaching here from elsewhere is still declared honestly.
      mimeType: _mimeFor(name),
      purity: image.tier == StorageTier.appPrivate ? Purity.nsfw : Purity.sfw,
    );
  }

  /// The type a receiver should file it under, from the extension.
  ///
  /// Extension-based rather than sniffed: the bytes are on the platform's side
  /// of a SAF boundary here, and every file tela writes it named itself.
  static String _mimeFor(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

/// Files ready to beam, and the throwaway copies made to get them.
class ResolvedBeamFiles {
  /// Bundles the resolved [files] with the previews owed a release.
  const ResolvedBeamFiles({
    required this.files,
    required LocalPreviewCache previews,
    required List<LocalPreview> temporary,
  }) : _previews = previews,
       _temporary = temporary;

  final LocalPreviewCache _previews;
  final List<LocalPreview> _temporary;

  /// What to hand the beam.
  final List<BeamFile> files;

  /// Deletes every throwaway copy this resolution made.
  ///
  /// Safe to call twice, and safe when nothing was temporary — releasing a
  /// non-temporary preview is a documented no-op, because that path is the
  /// download's own file and never tela's to delete.
  Future<void> release() async {
    for (final LocalPreview preview in _temporary) {
      await _previews.release(preview);
    }
    _temporary.clear();
  }
}
