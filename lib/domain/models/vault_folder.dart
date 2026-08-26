import 'package:meta/meta.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// The hidden directory explicit downloads land in on the files tier.
///
/// The files-outside-gallery tier writes safe downloads to a `tela` folder the
/// user can find. Explicit ones go to a **dot-prefixed sibling** — `.tela` by
/// default — so a file manager listing the granted folder shows one directory
/// rather than two until hidden files are deliberately turned on.
///
/// **Concealment, not security, and the app must not imply otherwise.** A dot
/// is a convention any file manager can switch off, and a card reads in any
/// other device. What actually holds is the rule above it: nothing tela stores
/// is ever MediaStore-indexed unless it is safe, so these never reach Photos
/// however they are stored.
///
/// A **label**, not a path. The caller names `tela` and the dot is composed
/// here, which is what makes it impossible to drop and impossible to double:
/// someone typing `stash` and someone typing `.stash` are asking for the same
/// folder, and only one of those spellings is a legal label.
///
/// ```dart
/// VaultFolder.standard.directoryName;   // '.tela'
/// VaultFolder('stash').directoryName;   // '.stash'
/// ```
@immutable
class VaultFolder {
  /// Creates a vault, refusing a label that could not be a folder.
  ///
  /// Throws [ArgumentError] rather than repairing it, exactly as [TagFolder]
  /// does and for the same reason: a caller holding a string of unknown shape
  /// wants [sanitize], and quietly turning `../secrets` into `secrets` would
  /// hide files somewhere nobody asked for.
  VaultFolder(this.label) {
    if (!isLegal(label)) {
      throw ArgumentError(
        'vault label must be 1-32 characters of letters, digits, space, _ or '
        '-, with no leading dot, got "$label"',
      );
    }
  }

  const VaultFolder._(this.label);

  /// The vault used until the user picks another.
  static const VaultFolder standard = VaultFolder._('tela');

  /// The name the user types and the settings row shows, without the dot.
  final String label;

  /// The directory on disk — the label, hidden.
  String get directoryName => '.$label';

  /// Whether [label] may name a vault.
  ///
  /// **The same allowlist a tag passes**, deliberately: this crosses a method
  /// channel and becomes a directory name, so `..` and separators have to be
  /// unreachable. The dot that hides the folder is added by [directoryName] and
  /// is never part of the label, which is what lets this guard stay exactly as
  /// strict as the tag one rather than growing an exception for the one
  /// character it needs.
  static bool isLegal(String label) => TagFolder.isLegal(label);

  /// Reads [raw] as a label, or null when nothing legal survives.
  ///
  /// For the settings field, where the string is whatever was typed. A leading
  /// dot is **dropped before sanitizing** rather than refused: someone typing
  /// `.stash` is naming the folder they can see, not making a mistake, and the
  /// dot they typed is the one this class adds back.
  static VaultFolder? sanitize(String raw) {
    final String withoutDot = raw.startsWith('.') ? raw.substring(1) : raw;
    final TagFolder? legal = TagFolder.sanitize(withoutDot);
    if (legal == null) return null;
    return VaultFolder._(legal.name);
  }

  @override
  bool operator ==(Object other) =>
      other is VaultFolder && other.label == label;

  @override
  int get hashCode => label.hashCode;

  /// Names the folder and nothing in it. Safe to print for the same reason
  /// [TagFolder.toString] is: it carries no location and no file.
  @override
  String toString() => directoryName;
}
