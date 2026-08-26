import 'package:meta/meta.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_target.dart';

/// How often auto-rotate changes the wallpaper.
///
/// The values are minutes because that is what the platform scheduler takes,
/// and the shortest is fifteen because that is the floor WorkManager enforces
/// on periodic work — asking for less does not fail, it is silently rounded up,
/// which would make a "every 5 minutes" setting a lie.
enum RotationInterval {
  /// The platform floor. Mostly useful for seeing that it works at all.
  quarterHour(15),

  /// Hourly.
  hourly(60),

  /// Four times a day.
  sixHourly(360),

  /// Once a day — the interval PLAN.md names.
  daily(1440);

  const RotationInterval(this.minutes);

  /// How many minutes between changes.
  final int minutes;

  /// Reads a stored value, answering null for one this build has no name for.
  static RotationInterval? tryFromMinutes(int minutes) => RotationInterval
      .values
      .where((RotationInterval each) => each.minutes == minutes)
      .firstOrNull;
}

/// Which pile of already-downloaded wallpapers auto-rotate draws from.
///
/// Downloads rather than a live listing, and that is the load-bearing choice:
/// a schedule that searched would spend the 45/minute ceiling in the
/// background, need a network at whatever hour it fires, and could hand the
/// screen a wallpaper nobody has ever seen. Every candidate here is a file the
/// user already chose to keep.
enum RotationSource {
  /// Everything in the shared gallery tier.
  gallery(StorageTier.sharedGallery),

  /// Everything in the files-outside-gallery tier — the desktop-sync path.
  filesOutsideGallery(StorageTier.filesOutsideGallery),

  /// The private library.
  ///
  /// **Its own choice, never folded into an "everything" option.** A rotation
  /// puts its pick on the home or lock screen, where anyone glancing at the
  /// phone sees it — so an explicit wallpaper arriving there must be something
  /// the user asked for by name, not a side effect of picking "all my
  /// downloads". This is the same shape as the beam's opt-in gate, for the same
  /// reason.
  privateLibrary(StorageTier.appPrivate);

  const RotationSource(this.tier);

  /// The storage tier this source reads.
  final StorageTier tier;
}

/// The whole auto-rotate configuration, as one value.
///
/// One object rather than four settings because they are only ever read
/// together and only ever written together: the platform schedule is
/// re-enqueued whenever any of them changes, so a partial update is a state
/// that cannot be acted on.
///
/// ```dart
/// const RotationPlan(
///   interval: RotationInterval.daily,
///   source: RotationSource.gallery,
///   target: WallpaperTarget.home,
/// );
/// ```
@immutable
class RotationPlan {
  /// Creates a plan.
  const RotationPlan({
    required this.interval,
    required this.source,
    required this.target,
  });

  /// What a fresh install would rotate on, if it were switched on untouched.
  ///
  /// Daily, from the gallery, onto the home screen: the least surprising of
  /// every axis, and explicitly *not* the private library.
  static const RotationPlan defaults = RotationPlan(
    interval: RotationInterval.daily,
    source: RotationSource.gallery,
    target: WallpaperTarget.home,
  );

  /// How often to change.
  final RotationInterval interval;

  /// Where the candidates come from.
  final RotationSource source;

  /// Which surface to set — home, lock, or both.
  final WallpaperTarget target;

  /// This plan with one field replaced.
  RotationPlan copyWith({
    RotationInterval? interval,
    RotationSource? source,
    WallpaperTarget? target,
  }) {
    return RotationPlan(
      interval: interval ?? this.interval,
      source: source ?? this.source,
      target: target ?? this.target,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RotationPlan &&
      other.interval == interval &&
      other.source == source &&
      other.target == target;

  @override
  int get hashCode => Object.hash(interval, source, target);
}
