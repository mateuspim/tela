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

  /// The tiers legal for **every** purity in [purities] — the intersection of
  /// [choicesFor], preserving [StorageTier.values] order.
  ///
  /// A batch download offers only these, so a mixed selection containing an
  /// explicit wallpaper is never offered the gallery and "one destination for
  /// all of them" stays literally true. An empty set answers the full list.
  ///
  /// ```dart
  /// StorageSettings.choicesForAll({Purity.sfw, Purity.nsfw}); // no gallery
  /// ```
  static List<StorageTier> choicesForAll(Set<Purity> purities) {
    return StorageTier.values
        .where(
          (StorageTier tier) =>
              purities.every((Purity p) => choicesFor(p).contains(tier)),
        )
        .toList();
  }

  /// The purity whose setting governs [purity]: [Purity.nsfw] for explicit
  /// content, [Purity.sfw] for everything else.
  ///
  /// The two-knobs-not-three rule, spelled once. Anything that keys storage
  /// *state* by purity — the configured tier, the destination streak — must key
  /// it through here, or `sketchy` quietly grows a bucket of its own that
  /// [tierFor] does not honour.
  ///
  /// ```dart
  /// StorageSettings.bucketFor(Purity.sketchy); // Purity.sfw
  /// ```
  static Purity bucketFor(Purity purity) {
    return purity == Purity.nsfw ? Purity.nsfw : Purity.sfw;
  }

  /// The configured destination for a wallpaper of [purity].
  StorageTier tierFor(Purity purity) {
    return bucketFor(purity) == Purity.nsfw ? nsfwTier : sfwTier;
  }

  /// Where a download of [purity] lands given an optional "Keep sending here"
  /// [pin] — the destination the user asked every download to go to.
  ///
  /// The pin wins over the per-purity configured tier when it is legal for
  /// [purity]. The one illegal pairing is an explicit wallpaper under a
  /// [StorageTier.sharedGallery] pin: it falls back to [tierFor], keeping the
  /// NSFW invariant that lives in this class rather than bolting a per-item
  /// exception onto the caller. A null pin routes by [tierFor] as usual.
  ///
  /// ```dart
  /// // sfwGallery pin, explicit wallpaper → configured (private) tier
  /// settings.tierWithPin(Purity.nsfw, StorageTier.sharedGallery);
  /// ```
  StorageTier tierWithPin(Purity purity, StorageTier? pin) {
    if (pin != null && choicesFor(purity).contains(pin)) return pin;
    return tierFor(purity);
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
