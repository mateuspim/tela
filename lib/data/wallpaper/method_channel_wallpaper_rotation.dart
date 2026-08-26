import 'package:flutter/services.dart';
import 'package:tela/domain/models/rotation_plan.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_rotation.dart';

/// [WallpaperRotation] over the native WorkManager schedule.
///
/// Only ever starts, stops and describes — the rotation itself runs in
/// `WallpaperRotationWorker` with no Dart alive, so nothing here can change a
/// wallpaper.
///
/// The granted SAF tree and the vault label are deliberately **not** sent: they
/// live in native preferences and the worker reads them at run time, so a
/// schedule made months ago follows a vault the user has since moved.
class MethodChannelWallpaperRotation implements WallpaperRotation {
  /// Creates the adapter over the rotation channel.
  const MethodChannelWallpaperRotation([
    this._channel = const MethodChannel('cc.pym.tela/rotation'),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> start(RotationPlan plan) {
    return _channel.invokeMethod<void>('start', <String, Object?>{
      'intervalMinutes': plan.interval.minutes,
      'tier': plan.source.tier.name,
      'target': plan.target.name,
    });
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<RotationPlan?> current() async {
    final Map<Object?, Object?>? raw = await _channel
        .invokeMethod<Map<Object?, Object?>>('current');
    if (raw == null) return null;
    return _planFrom(raw);
  }

  /// Reads the native answer, treating anything unrecognisable as "off".
  ///
  /// Null rather than a fallback plan: a schedule this build cannot describe is
  /// one whose settings screen would misreport it, and claiming rotation is off
  /// when the platform disagrees is the safer of the two wrong answers — the
  /// user's next toggle re-enqueues it either way.
  static RotationPlan? _planFrom(Map<Object?, Object?> raw) {
    final Object? minutes = raw['intervalMinutes'];
    final RotationInterval? interval = minutes is int
        ? RotationInterval.tryFromMinutes(minutes)
        : null;
    final RotationSource? source = _sourceFrom(raw['tier']);
    final WallpaperTarget? target = _targetFrom(raw['target']);
    if (interval == null || source == null || target == null) return null;
    return RotationPlan(interval: interval, source: source, target: target);
  }

  static RotationSource? _sourceFrom(Object? tier) => RotationSource.values
      .where((RotationSource each) => each.tier.name == tier)
      .firstOrNull;

  static WallpaperTarget? _targetFrom(Object? name) => WallpaperTarget.values
      .where((WallpaperTarget each) => each.name == name)
      .firstOrNull;
}
