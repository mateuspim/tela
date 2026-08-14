import 'package:tela/domain/models/clipboard_confirmation.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';
import 'package:tela/domain/ports/wallpaper_sharer.dart';

/// In-memory [WallpaperSharer] that records what it was asked to share.
class FakeWallpaperSharer implements WallpaperSharer {
  /// Creates a fake that succeeds unless [failure] is set, in which case every
  /// call throws it.
  FakeWallpaperSharer({
    this.failure,
    this.confirmation = ClipboardConfirmation.tela,
  });

  /// Operational failure thrown by every call, when set.
  final WallpaperShareFailure? failure;

  /// What [copyImage] reports back — who confirmed the copy to the user.
  final ClipboardConfirmation confirmation;

  /// Every page URL passed to [shareLink], in order.
  final List<Uri> sharedLinks = <Uri>[];

  /// Every (source, fileName) pair passed to [shareImage], in order.
  final List<({Uri source, String fileName})> sharedImages =
      <({Uri source, String fileName})>[];

  /// Every (source, fileName, sensitive) triple passed to [copyImage], in
  /// order. `sensitive` is the flag that keeps an explicit copy out of the
  /// system's clipboard preview, so a test may assert it was carried.
  final List<({Uri source, String fileName, bool sensitive})> copiedImages =
      <({Uri source, String fileName, bool sensitive})>[];

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

  @override
  Future<ClipboardConfirmation> copyImage({
    required Uri source,
    required String fileName,
    required bool sensitive,
  }) async {
    copiedImages.add((
      source: source,
      fileName: fileName,
      sensitive: sensitive,
    ));
    final WallpaperShareFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
    return confirmation;
  }
}
