import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// One download's answer: where it lands, and whether that answer sticks.
///
/// [remember] is only ever true for the streak destination — the "Always
/// save … here" affordance, which both sends this download there *and* asks the
/// caller to persist it as the bucket's per-purity default (I3). [pin] is the
/// "Keep sending here" toggle: it asks the caller to make [tier] the
/// purity-flat pin every later download follows (K2). A plain destination tap
/// leaves both false: this one download moves, nothing else does.
///
/// A choice that only [stopsPin] carries a null [tier] and downloads nothing —
/// it is the chooser's Stop affordance, clearing an active pin and no more.
@immutable
class DownloadDestinationChoice {
  /// Creates a choice of [tier], optionally asking to [remember] or [pin] it.
  const DownloadDestinationChoice({
    required this.tier,
    this.remember = false,
    this.pin = false,
    this.tag,
    this.rememberTag = false,
  });

  /// A choice that only clears the "Keep sending here" pin — nothing downloads.
  const DownloadDestinationChoice.stopPin()
    : tier = null,
      remember = false,
      pin = false,
      tag = null,
      rememberTag = false;

  /// Where this download should land, or null when the choice only [stopsPin].
  final StorageTier? tier;

  /// Whether to also make [tier] the per-purity configured default (I3's
  /// "Always"). Independent of [pin].
  final bool remember;

  /// Whether to make [tier] the purity-flat "Keep sending here" pin (K2).
  final bool pin;

  /// The tag folder this download is filed under, or null for the tier's root.
  ///
  /// Independent of [tier] in a way [remember] and [pin] are not: a tag has no
  /// purity rule and no configured default behind it. It is simply the folder
  /// the user picked, or did not.
  final TagFolder? tag;

  /// Whether [tag] should be offered first next time — the tag's counterpart
  /// to [pin], and deliberately a *suggestion* rather than a standing order.
  /// A remembered tag still shows in the chooser and can still be changed.
  final bool rememberTag;

  /// Whether this choice only clears the pin and downloads nothing — true
  /// exactly when [tier] is null.
  bool get stopsPin => tier == null;
}
