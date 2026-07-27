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

  /// Reads back a [key] — `'wallhaven-e7jvjd'` — into its two halves.
  ///
  /// The inverse of [key], and it exists for the one place a ref is stored as
  /// a flat string rather than two columns: the **name of a downloaded file**.
  /// The app-private tier writes no history row, so a private image's source
  /// survives only in its file name.
  ///
  /// Splitting on the *first* `-` is unambiguous because [SourceId] admits no
  /// hyphen, and the storage adapter refuses to write an id containing one.
  ///
  /// Throws [ArgumentError] for anything that is not two non-empty halves,
  /// rather than guessing — attributing one source's wallpaper to another is
  /// exactly the silent error this type was introduced to stop.
  ///
  /// ```dart
  /// WallpaperRef.parse('konachan-406484').id; // '406484'
  /// ```
  factory WallpaperRef.parse(String key) {
    return WallpaperRef.tryParse(key) ??
        (throw ArgumentError('wallpaper ref must be "source-id", got "$key"'));
  }

  /// The same read as [WallpaperRef.parse], answering null instead of throwing.
  ///
  /// The form the private-tier listing wants: that directory holds file names
  /// tela wrote, but nothing stops a user putting their own file beside them,
  /// and one such file must cost its own tile rather than the whole library.
  static WallpaperRef? tryParse(String key) {
    final int split = key.indexOf('-');
    if (split <= 0 || split == key.length - 1) return null;
    final SourceId? source = SourceId.tryParse(key.substring(0, split));
    if (source == null) return null;
    return WallpaperRef(source, key.substring(split + 1));
  }

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
