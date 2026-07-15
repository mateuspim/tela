import 'package:tela/domain/models/wallpaper_share_failure.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';

/// In-memory [WallpaperSharer] that records what it was asked to share.
class FakeWallpaperSharer implements WallpaperSharer {
  /// Creates a fake that succeeds unless [failure] is set, in which case every
  /// call throws it.
  FakeWallpaperSharer({this.failure});

  /// Operational failure thrown by every call, when set.
  final WallpaperShareFailure? failure;

  /// Every page URL passed to [shareLink], in order.
  final List<Uri> sharedLinks = <Uri>[];

  /// Every (source, fileName) pair passed to [shareImage], in order.
  final List<({Uri source, String fileName})> sharedImages =
      <({Uri source, String fileName})>[];

  @override
  Future<void> shareLink(Uri page) async {
    sharedLinks.add(page);
    final WallpaperShareFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
  }

  @override
  Future<void> shareImage({
    required Uri source,
    required String fileName,
  }) async {
    sharedImages.add((source: source, fileName: fileName));
    final WallpaperShareFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
  }
}
