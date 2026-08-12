import 'package:meta/meta.dart';

/// A tag the user files downloads under — which, on disk, is a folder.
///
/// A tag in tela is not a label in a table. It is a real directory inside
/// whichever tier the download lands in: `Pictures/tela/anime`, the files
/// tier's `tela/anime`, the private library's `wallpapers/anime`. That is what
/// makes a tag organize the library in Photos, in a file manager and over USB
/// rather than only inside the app — and it is the only way the **app-private
/// tier** can be organized at all, because that tier deliberately writes no
/// database row and a table of what is in it would be the ungated, backed-up
/// index it exists to prevent.
///
/// Being a directory name is why this is a type and not a `String`. The name
/// crosses a method channel and is concatenated into a path, so what may become
/// a path segment has to be decided in one place; the Kotlin side applies the
/// same allowlist again, because that is the side holding the file system.
///
/// ```dart
/// const TagFolder('anime').name;        // 'anime'
/// TagFolder.sanitize('long hair');      // TagFolder('long hair')
/// TagFolder.sanitize('..');             // null
/// ```
@immutable
class TagFolder {
  /// Creates a tag, refusing anything that could not be a folder.
  ///
  /// Throws [ArgumentError] rather than repairing the name: a caller with a
  /// string of unknown shape — a tag off a wallpaper, a line the user typed —
  /// wants [sanitize], and quietly turning `../secrets` into `secrets` would
  /// file a download somewhere nobody asked for.
  TagFolder(this.name) {
    if (!isLegal(name)) {
      throw ArgumentError(
        'tag must be 1-32 characters of letters, digits, space, _ or -, '
        'not starting or ending with a space, got "$name"',
      );
    }
  }

  const TagFolder._(this.name);

  /// The tag as the user sees it, and as the directory is named.
  final String name;

  /// The longest a tag may be. Comfortably inside every filesystem's limit,
  /// and short enough to render in a chip without eliding.
  static const int maxLength = 32;

  /// Reads [raw] as a tag, repairing what can be repaired and answering null
  /// when nothing legal survives.
  ///
  /// The door for names tela did not invent: a source's own tag
  /// (`hatsune_miku`, `long hair`, `>_<`) or a line typed into the chooser.
  /// Whitespace is trimmed and collapsed, illegal characters are dropped, and
  /// the result is capped at [maxLength].
  ///
  /// **Dropping rather than substituting** is deliberate. A tag is matched
  /// against the folders that already exist, so a repair that invents
  /// characters — `sci-fi` from `sci/fi` — makes a second folder that looks
  /// like one the user already has. Losing a character the filesystem could not
  /// have held is honest; adding one is not.
  ///
  /// **A result with no letter or digit in it is dropped**, which is a rule
  /// about real booru tags rather than a tidiness preference. Konachan carries
  /// emoticon tags — `>_<`, `^_^`, `:d` — and `_` and `-` survive sanitizing,
  /// so those reduce to `_`, `_`, and `d`. A folder called `_` is meaningless
  /// on its own, and worse, *several different* emoticon tags collapse onto the
  /// same one: their counts add up and the residue can outrank the tag that
  /// actually describes the selection.
  ///
  /// Answers null, never a throw: a source tag that reduces to nothing is an
  /// ordinary thing to find in a list of candidates, not an error.
  static TagFolder? sanitize(String raw) {
    final String kept = raw.replaceAll(_illegal, ' ');
    final String collapsed = kept.replaceAll(_runOfSpaces, ' ').trim();
    if (collapsed.isEmpty) return null;
    final String capped = collapsed.length <= maxLength
        ? collapsed
        // Trimmed again: the cut can land immediately after a space.
        : collapsed.substring(0, maxLength).trimRight();
    if (!_meaningful.hasMatch(capped)) return null;
    return TagFolder._(capped);
  }

  /// Whether [name] may be used as a folder exactly as it stands.
  ///
  /// Public because the chooser asks it of what is being typed, before there is
  /// a tag to construct.
  static bool isLegal(String name) => _legal.hasMatch(name);

  /// Two tags are the same tag when their names match, case included.
  ///
  /// Case-sensitive on purpose, even though shared storage is not: `Anime` and
  /// `anime` are one directory on the device, so treating them as one tag here
  /// would let the app show two chips for one folder. Keeping them distinct
  /// keeps the model honest about what the user typed; the *folder* they land
  /// in is the filesystem's business, and it will merge them itself.
  @override
  bool operator ==(Object other) => other is TagFolder && other.name == name;

  @override
  int get hashCode => name.hashCode;

  /// Names the tag, and nothing about where it lives.
  ///
  /// A private-library tag is a private string — "waifus" says as much as a
  /// file path does — so this is safe to print only because it carries no
  /// location. The same rule `PrivateImage.toString` follows.
  @override
  String toString() => name;

  /// Letters, digits, space, `_` and `-`; no leading or trailing space.
  ///
  /// Mirrors Kotlin's `TagFolders.VALID_TAG` exactly, and the two are meant to
  /// stay that way: a name this side accepts and that side refuses is a
  /// download that fails with `unavailable` for no reason the user can see.
  ///
  /// **No `.` at all**, which is the traversal guard doing its work without a
  /// rule per case: `..`, `.nomedia` and hidden directories all stop being
  /// expressible. A space is allowed inside but not at either end — `" anime"`
  /// renders identically to `"anime"` in every list the user will ever read
  /// while being a different directory on disk.
  static final RegExp _legal = RegExp(
    r'^[A-Za-z0-9_-]([A-Za-z0-9 _-]{0,30}[A-Za-z0-9_-])?$',
  );

  /// Everything [sanitize] replaces with a space before collapsing.
  static final RegExp _illegal = RegExp('[^A-Za-z0-9 _-]');

  static final RegExp _runOfSpaces = RegExp(' {2,}');

  /// At least one letter or digit. What separates a tag from the punctuation
  /// left over when an emoticon tag is stripped of what a folder cannot hold.
  static final RegExp _meaningful = RegExp('[A-Za-z0-9]');
}
