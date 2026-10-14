/// What a quick look at a stored image's bytes says about it.
///
/// Judged from the file's size and its two ends, never a full decode — see
/// `ImageStore.inspectAll`. Only [empty] and [truncated] count as broken:
/// [unreadable] is a file tela could not open, which is a revoked grant or an
/// ejected card far more often than damage, and the repair must not overwrite
/// or delete what it merely could not see.
///
/// ```dart
/// StoredImageCondition.truncated.isBroken; // true
/// ```
enum StoredImageCondition {
  /// Opens, and ends where its format says it must.
  intact,

  /// Zero bytes — a write that created the file and never filled it.
  empty,

  /// Stops before its format's end marker — a write cut off part-way.
  truncated,

  /// Could not be opened at all. Not a verdict on the bytes.
  unreadable;

  /// Whether the repair should replace this file.
  bool get isBroken => this == empty || this == truncated;
}
