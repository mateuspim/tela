import 'package:meta/meta.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// Where downloads land, configured for safe and explicit content separately.
///
/// Two knobs, not three: `sketchy` follows [sfwTier]. Wallhaven treats sketchy
/// as suggestive-but-not-explicit, and only [Purity.nsfw] carries the rules in
/// the NSFW section of CLAUDE.md, so it is the only purity that earns its own
/// destination.
///
/// ```dart
/// StorageSettings.defaults.tierFor(Purity.nsfw); // StorageTier.appPrivate
/// ```
@immutable
class StorageSettings {
  /// Creates settings, rejecting any destination that would index NSFW media.
  StorageSettings({required this.sfwTier, required this.nsfwTier}) {
    if (nsfwTier == StorageTier.sharedGallery) {
      throw ArgumentError(
        'nsfw tier must be filesOutsideGallery|appPrivate, '
        'got "${nsfwTier.name}"',
      );
    }
  }

  /// The privacy-preserving routing used until the user changes it.
  static final StorageSettings defaults = StorageSettings(
    sfwTier: StorageTier.sharedGallery,
    nsfwTier: StorageTier.appPrivate,
  );

  /// Destination for `sfw` and `sketchy` downloads.
  final StorageTier sfwTier;

  /// Destination for `nsfw` downloads. Never [StorageTier.sharedGallery]:
  /// that tier is MediaStore-indexed, which NSFW files may never be.
  final StorageTier nsfwTier;

  /// The tiers a user may pick for [purity], in the order a picker shows them.
  ///
  /// The NSFW invariant is a property of the settings, not of the settings UI,
  /// so the screen asks the domain rather than hardcoding a shorter list.
  static List<StorageTier> choicesFor(Purity purity) {
    if (purity != Purity.nsfw) return StorageTier.values;
    return StorageTier.values
        .where((StorageTier tier) => tier != StorageTier.sharedGallery)
        .toList();
  }

  /// The configured destination for a wallpaper of [purity].
  StorageTier tierFor(Purity purity) {
    return purity == Purity.nsfw ? nsfwTier : sfwTier;
  }

  /// Returns a copy with one tier replaced.
  StorageSettings copyWith({StorageTier? sfwTier, StorageTier? nsfwTier}) {
    return StorageSettings(
      sfwTier: sfwTier ?? this.sfwTier,
      nsfwTier: nsfwTier ?? this.nsfwTier,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StorageSettings &&
        other.sfwTier == sfwTier &&
        other.nsfwTier == nsfwTier;
  }

  @override
  int get hashCode => Object.hash(sfwTier, nsfwTier);

  @override
  String toString() =>
      'StorageSettings(sfw: ${sfwTier.name}, nsfw: ${nsfwTier.name})';
}
