import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// In-memory [WallpaperApplier] that records the sources it was asked to apply.
class FakeWallpaperApplier implements WallpaperApplier {
  /// Creates a fake that succeeds unless the source is in [unreadableSources],
  /// or [failure] is set.
  ///
  /// [unreadableSources] stands in for a downloaded file the user has since
  /// deleted: applying it raises [WallpaperApplyProblem.source] while the same
  /// wallpaper's Wallhaven URL still works — exactly the split `ApplyDownload`
  /// falls back on.
  FakeWallpaperApplier({
    this.failure,
    Set<Uri> unreadableSources = const <Uri>{},
  }) : _unreadableSources = unreadableSources;

  /// Operational failure thrown by every call, when set.
  final WallpaperApplyFailure? failure;

  final Set<Uri> _unreadableSources;

  /// Every source applied, in order.
  final List<Uri> receivedSources = <Uri>[];

  /// Source from the latest call.
  Uri? get receivedSource => receivedSources.lastOrNull;

  /// Android surface from the latest call.
  WallpaperTarget? receivedTarget;

  /// Number of apply attempts.
  int get callCount => receivedSources.length;

  @override
  Future<void> apply({
    required Uri source,
    required WallpaperTarget target,
  }) async {
    receivedSources.add(source);
    receivedTarget = target;
    if (_unreadableSources.contains(source)) {
      throw const WallpaperApplyFailure(WallpaperApplyProblem.source);
    }
    final WallpaperApplyFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
  }
}
