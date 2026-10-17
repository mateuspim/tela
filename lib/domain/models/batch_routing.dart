import 'package:meta/meta.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// How a batch download is routed: an explicit batch lands together.
///
/// A batch that holds — or, for a whole listing, *may* hold — an explicit
/// wallpaper is routed **as explicit, all of it**: every image follows the
/// explicit destination and the explicit folder. Routing each image by its
/// own purity split one batch across the gallery and the card, a hundred
/// images here and a hundred there (owner, 2026-10-16). The strict side is the
/// only safe one to round to: a safe image in the vault is harmless, an
/// explicit one in the gallery is what the NSFW rules exist to prevent.
///
/// ```dart
/// final BatchRouting routing =
///     BatchRouting(<Purity>{Purity.sfw, Purity.nsfw});
/// routing.purities; // {Purity.nsfw}
/// routing.apply(selection); // every wallpaper routed as explicit
/// ```
@immutable
class BatchRouting {
  /// Routes a batch whose wallpapers are of [batchPurities].
  const BatchRouting(this.batchPurities);

  /// The purities the batch holds or may hold.
  final Set<Purity> batchPurities;

  /// Whether the batch lands together under the explicit rules.
  bool get isExplicit => batchPurities.contains(Purity.nsfw);

  /// The purities the batch is routed as — just [Purity.nsfw] for an
  /// explicit batch, otherwise what it holds.
  Set<Purity> get purities =>
      isExplicit ? <Purity>{Purity.nsfw} : batchPurities;

  /// [batch] as it should be queued: each wallpaper routed as explicit when
  /// [isExplicit], untouched otherwise.
  List<Wallpaper> apply(List<Wallpaper> batch) {
    if (!isExplicit) return batch;
    return <Wallpaper>[
      for (final Wallpaper wallpaper in batch) wallpaper.routedAsExplicit(),
    ];
  }
}
