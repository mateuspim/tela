import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/ports/dominant_color.dart';

/// A [DominantColor] that answers whatever the test decided, per image.
///
/// Named rather than inline, and a class rather than a stub, so a test that
/// cares which URL was read can say so: the whole point of the fallback is
/// that it is asked *only* for a source with no palette of its own.
class FakeDominantColor implements DominantColor {
  /// Answers [colour] for any image, unless [byUrl] names one.
  FakeDominantColor({this.colour, this.byUrl = const <String, String>{}});

  /// The colour every unnamed image reports, as `#rrggbb`. Null means none.
  final String? colour;

  /// Per-image answers, for a test walking more than one wallpaper.
  final Map<String, String> byUrl;

  /// Every image this was asked about, in order — so a test can prove it was
  /// never asked at all.
  final List<String> asked = <String>[];

  @override
  Future<WallpaperColor?> of(String imageUrl) async {
    asked.add(imageUrl);
    final String? hex = byUrl[imageUrl] ?? colour;
    return hex == null ? null : WallpaperColor(hex);
  }
}
