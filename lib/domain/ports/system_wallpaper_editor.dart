import 'package:tela/domain/models/wallpaper_adjust_failure.dart';

/// Hands a wallpaper to Android's own crop-and-set editor.
///
/// This is the OEM's wallpaper picker — on a Samsung, the same screen the
/// gallery opens, with reposition and the clock and widget preview. tela stops
/// at the hand-off: the editor owns the crop, the Home/Lock/Both choice, and
/// the apply itself, so unlike `WallpaperApplier` there is **no result to
/// report**. A caller learns only that the editor opened.
///
/// Callers must not pass an explicit wallpaper here — its pixels would reach a
/// separate app with its own wallpaper history, which `mayExportBitmap` refuses
/// and `AdjustWallpaper` enforces.
abstract interface class SystemWallpaperEditor {
  /// Fetches [source] and opens the system editor on it, naming the file
  /// [fileName] so the editor keeps a sensible name and extension.
  ///
  /// Throws [WallpaperAdjustFailure] when the image cannot be fetched, when no
  /// editor exists on the device, or when the platform rejects the image. Never
  /// includes [source] in the thrown value.
  Future<void> openFor({required Uri source, required String fileName});
}
