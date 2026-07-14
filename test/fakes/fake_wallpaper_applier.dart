import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_applier.dart';

/// In-memory [WallpaperApplier] that records the requested image and target.
class FakeWallpaperApplier implements WallpaperApplier {
  /// Creates a fake that succeeds unless [failure] is provided.
  FakeWallpaperApplier({this.failure});

  /// Operational failure thrown by every call, when set.
  final WallpaperApplyFailure? failure;

  /// Full-resolution URL from the latest call.
  String? receivedImageUrl;

  /// Android surface from the latest call.
  WallpaperTarget? receivedTarget;

  /// Number of apply attempts.
  int callCount = 0;

  @override
  Future<void> apply({
    required String imageUrl,
    required WallpaperTarget target,
  }) async {
    callCount += 1;
    receivedImageUrl = imageUrl;
    receivedTarget = target;
    final WallpaperApplyFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
  }
}
