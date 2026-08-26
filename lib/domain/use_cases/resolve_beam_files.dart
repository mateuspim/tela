import 'package:meta/meta.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/local_preview.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_file_name.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
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
/// One image a beam has been asked to send, before its bytes are reachable.
///
/// The two shelves that can beam hold different types — the private library
/// has [PrivateImage], the download history has [DownloadRecord] — and only
/// this much of either matters. Naming it keeps [ResolveBeamFiles] from
/// knowing about both, and keeps the purity rule at the two call sites where
/// it is actually decidable.
@immutable
class BeamCandidate {
  /// Creates a candidate.
  const BeamCandidate({
    required this.ref,
    required this.location,
    required this.sizeBytes,
    required this.purity,
    required this.fileName,
  });

  /// Everything in the private library, at **either** of its two homes.
  ///
  /// **Always explicit, and never read off the tier.** The private library has
  /// two homes since the vault — the app-private tier, and the hidden folder on
  /// `filesOutsideGallery` that explicit downloads land in once the destination
  /// points at a card. They render identically and sit behind the same lock, so
  /// deciding purity from the tier would mark every vault image safe and beam
  /// it straight past the opt-in gate. The library *is* the explicit tier;
  /// which disk it happens to be on says nothing about the picture.
  factory BeamCandidate.ofPrivate(PrivateImage image) => BeamCandidate(
    ref: image.ref,
    location: image.location,
    sizeBytes: image.sizeBytes,
    purity: Purity.nsfw,
    // Composed from the ref, never lifted whole from the path — the same rule
    // `wallpaperFileName` states and for the same reason: a booru names its
    // files after the tags on the image, and this is the explicit library.
    fileName: '${image.ref.key}${_extensionIn(image.location.toString())}',
  );

  /// One wallpaper that has **not** been downloaded, fetched on the way out.
  ///
  /// The location is the source's own image URL rather than a path, which
  /// [ResolveBeamFiles] recognises and fetches once into the preview cache.
  /// Without this a beam could only ever send what was already on the device,
  /// which is not what "send this wallpaper to my computer" means when you are
  /// looking at one you have never downloaded.
  factory BeamCandidate.ofWallpaper(Wallpaper wallpaper) => BeamCandidate(
    ref: wallpaper.ref,
    location: Uri.parse(wallpaper.fullImageUrl),
    sizeBytes: wallpaper.fileSizeBytes,
    purity: wallpaper.purity,
    fileName: wallpaperFileName(wallpaper),
  );

  /// One downloaded wallpaper, carrying the purity the source published.
  ///
  /// Unlike the private library this is a real per-file answer, so a history
  /// holding a mix beams the safe ones and is refused for the explicit ones
  /// exactly as `BeamWallpapers` describes.
  factory BeamCandidate.ofDownload(DownloadRecord record) => BeamCandidate(
    ref: record.wallpaper.ref,
    location: record.location,
    sizeBytes: record.wallpaper.fileSizeBytes,
    purity: record.wallpaper.purity,
    // The shared helper the share sheet and the system editor already use, so
    // the same wallpaper arrives under the same name however it left.
    fileName: wallpaperFileName(record.wallpaper),
  );

  /// Which source issued it and under what id.
  final WallpaperRef ref;

  /// Where the bytes are — a `file:` path or a `content:` SAF document URI.
  final Uri location;

  /// How many bytes the receiver should expect.
  final int sizeBytes;

  /// How explicit it is, so the beam gate can be applied per file.
  final Purity purity;

  /// The name the receiver should write it under.
  ///
  /// **Carried rather than read off the resolved path, which is what shipped
  /// wrong.** A materialized SAF or MediaStore source is a *cache copy*, named
  /// something like `preview-221123410085484` with no extension at all — so a
  /// real transfer put exactly that on the desktop, an 11MB file nothing could
  /// recognise (seen on hardware, 2026-08-26).
  final String fileName;
}

/// The `.ext` at the end of [location], or an empty string when it has none.
///
/// An extensionless name beats a wrong one — the same judgement
/// `wallpaperFileName` makes. Reads the decoded string rather than the path
/// segments because a SAF document URI hides the real name inside a
/// percent-encoded document id.
String _extensionIn(String location) {
  final String decoded = Uri.decodeFull(location);
  final int dot = decoded.lastIndexOf('.');
  if (dot <= 0) return '';
  final String candidate = decoded.substring(dot);
  // Only a plausible extension: a dot elsewhere in a path or an id must not
  // become a suffix, and `.tela` — the vault's own hidden folder — is exactly
  // such a dot.
  return RegExp(r'^\.[A-Za-z0-9]{2,5}$').hasMatch(candidate) ? candidate : '';
}

/// Turns beam candidates into files a beam can actually read.
class ResolveBeamFiles {
  /// Creates the use case. Every collaborator is injected (CLAUDE.md).
  const ResolveBeamFiles(this._previews);

  final LocalPreviewCache _previews;

  /// Resolves [candidates], skipping any that cannot be read.
  ///
  /// A file that will not materialize is dropped rather than failing the
  /// batch: one unreadable image out of forty should cost itself, not the
  /// other thirty-nine, and the sheet reports how many are actually going.
  Future<ResolvedBeamFiles> call(List<BeamCandidate> candidates) async {
    final List<BeamFile> files = <BeamFile>[];
    final List<LocalPreview> temporary = <LocalPreview>[];
    for (final BeamCandidate candidate in candidates) {
      // A wallpaper being browsed has no bytes on the device, so its
      // "location" is the source's own URL and has to be fetched once. Same
      // cache, same release — see LocalPreviewCache.materializeRemote.
      final bool remote =
          candidate.location.scheme == 'http' ||
          candidate.location.scheme == 'https';
      final LocalPreview? preview = remote
          ? await _previews.materializeRemote(candidate.location)
          : await _previews.materialize(candidate.location);
      if (preview == null) continue;
      if (preview.isTemporary) temporary.add(preview);
      files.add(_fileFor(candidate, preview));
    }
    return ResolvedBeamFiles(
      files: files,
      previews: _previews,
      temporary: temporary,
    );
  }

  BeamFile _fileFor(BeamCandidate candidate, LocalPreview preview) {
    return BeamFile(
      id: '${candidate.ref.source.value}-${candidate.ref.id}',
      // The candidate's name, not the resolved path's: that path is a cache
      // copy for anything behind SAF or MediaStore.
      fileName: candidate.fileName,
      path: preview.path,
      sizeBytes: candidate.sizeBytes,
      mimeType: _mimeFor(candidate.fileName),
      // Decided by the caller, never re-derived here: only the shelf knows
      // whether it is showing the explicit library or a mixed history.
      purity: candidate.purity,
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
