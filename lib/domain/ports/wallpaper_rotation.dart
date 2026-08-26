import 'package:tela/domain/models/rotation_plan.dart';

/// Schedules the platform to change the wallpaper on its own.
///
/// A platform capability behind a project-owned interface, like every other one
/// here. The work itself runs with no Dart alive — see the native worker — so
/// this port only ever starts, stops, and describes a schedule; it never
/// performs a rotation.
///
/// **That the work is native rather than a headless Dart isolate is the design
/// decision worth not re-litigating.** A rotation needs to list a directory,
/// pick a file, and hand it to `WallpaperManager` — all of which the platform
/// can do alone. Starting a Flutter engine every fifteen minutes to reach the
/// same three calls would cost the battery the schedule is supposed to be cheap
/// about, and would fail whenever the engine could not start.
///
/// ```dart
/// await rotation.start(RotationPlan.defaults);
/// ```
abstract interface class WallpaperRotation {
  /// Starts rotating on [plan], replacing any existing schedule.
  ///
  /// Replacing rather than adding: two schedules would fight over the same
  /// screen, and the user only ever expressed one.
  Future<void> start(RotationPlan plan);

  /// Stops rotating. A no-op when nothing is scheduled.
  Future<void> stop();

  /// The plan currently scheduled, or null when rotation is off.
  ///
  /// Read from the platform rather than from tela's own settings on purpose:
  /// the schedule is the platform's, and it can outlive an app's stored
  /// preferences (a restored backup, a cleared database). Asking the scheduler
  /// is what keeps the switch honest about what is actually going to happen.
  Future<RotationPlan?> current();
}
