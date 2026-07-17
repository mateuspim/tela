import 'package:tela/domain/models/wallpaper_adjust_failure.dart';
import 'package:tela/domain/ports/system_wallpaper_editor.dart';

/// In-memory [SystemWallpaperEditor] that records what it was asked to open.
class FakeSystemWallpaperEditor implements SystemWallpaperEditor {
  /// Creates a fake that succeeds unless [failure] is set, in which case every
  /// call throws it.
  FakeSystemWallpaperEditor({this.failure});

  /// Operational failure thrown by every call, when set.
  final WallpaperAdjustFailure? failure;

  /// Every (source, fileName) pair passed to [openFor], in order.
  final List<({Uri source, String fileName})> opened =
      <({Uri source, String fileName})>[];

  @override
  Future<void> openFor({required Uri source, required String fileName}) async {
    opened.add((source: source, fileName: fileName));
    final WallpaperAdjustFailure? toThrow = failure;
    if (toThrow != null) throw toThrow;
  }
}
