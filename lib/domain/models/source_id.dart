import 'package:meta/meta.dart';

/// Which site a wallpaper came from.
///
/// A value type rather than an enum: the registry is open — a test source, or
/// a booru added later, is one more adapter and one more constant, not an edit
/// to a closed set every `switch` in the app would then owe a case for.
///
/// The [value] is what reaches disk (the `source` column) and the front of a
/// downloaded file's name, so it is lowercase and stable forever: renaming one
/// orphans every stored row that used the old spelling.
///
/// ```dart
/// SourceId.wallhaven.value; // 'wallhaven'
/// ```
@immutable
class SourceId {
  /// Creates a source id from a literal. Use [SourceId.parse] for a value read
  /// back from storage or a URL, which is where a bad one can actually appear.
  const SourceId(this.value);

  /// Reads a source id that came from outside the code, rejecting a shape no
  /// adapter could ever have written.
  ///
  /// Throws [ArgumentError] rather than falling back, because every caller has
  /// a row or a route to blame and a silent default would attribute one
  /// source's wallpaper to another.
  factory SourceId.parse(String raw) {
    if (!_shape.hasMatch(raw)) {
      throw ArgumentError(
        'source id must be lowercase letters, digits or "_", got "$raw"',
      );
    }
    return SourceId(raw);
  }

  /// Wallhaven — the source tela shipped with, and the one every row written
  /// before schema v6 belongs to.
  static const SourceId wallhaven = SourceId('wallhaven');

  static final RegExp _shape = RegExp(r'^[a-z0-9_]+$');

  /// The stable identifier, e.g. `'wallhaven'`.
  final String value;

  @override
  bool operator ==(Object other) => other is SourceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
