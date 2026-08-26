import 'package:tela/domain/models/rotation_plan.dart';
import 'package:tela/domain/ports/wallpaper_rotation.dart';

/// In-memory [WallpaperRotation] that records every schedule it was given.
///
/// Records the whole history rather than just the latest, because the thing
/// worth asserting is that changing one setting *re-enqueues* — the platform
/// has no notion of editing periodic work, so a reshape that did not start
/// again would silently leave the old schedule running.
class FakeWallpaperRotation implements WallpaperRotation {
  /// Creates a fake already running [scheduled], or off when null.
  FakeWallpaperRotation({RotationPlan? scheduled}) : _current = scheduled;

  RotationPlan? _current;

  /// Every plan handed to [start], in order.
  final List<RotationPlan> started = <RotationPlan>[];

  /// How many times [stop] was called.
  int stops = 0;

  @override
  Future<void> start(RotationPlan plan) async {
    started.add(plan);
    _current = plan;
  }

  @override
  Future<void> stop() async {
    stops++;
    _current = null;
  }

  @override
  Future<RotationPlan?> current() async => _current;
}
