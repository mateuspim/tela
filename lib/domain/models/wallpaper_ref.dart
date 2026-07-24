import 'package:meta/meta.dart';
import 'package:tela/domain/models/source_id.dart';

/// What identifies one wallpaper, everywhere it is stored or ticked.
///
/// A bare id is not enough once there is more than one source: Wallhaven's ids
/// are base36 and a booru's are numeric, so nothing collides *today* — but
/// Konachan #12345 and yande.re #12345 are two different wallpapers, and a
/// favorites row keyed on the number alone would silently overwrite one with
/// the other.
///
/// ```dart
/// const WallpaperRef(SourceId.wallhaven, 'e7jvjd').key; // 'wallhaven-e7jvjd'
/// ```
@immutable
class WallpaperRef {
  /// Creates a reference to [id] as [source] issued it.
  const WallpaperRef(this.source, this.id);

  /// The site the wallpaper came from.
  final SourceId source;

  /// The id that site gave it, e.g. `'e7jvjd'` or `'406484'`. Unique within
  /// [source] and nowhere else.
  final String id;

  /// One flat string for the two, e.g. `'wallhaven-e7jvjd'`.
  ///
  /// The form a downloaded file is already named, so a file name and a
  /// selection tick agree without either one composing the pair by hand.
  String get key => '${source.value}-$id';

  @override
  bool operator ==(Object other) =>
      other is WallpaperRef && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => key;
}
