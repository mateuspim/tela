import 'package:meta/meta.dart';

/// Whether a [SearchTag] narrows a listing *to* its tag or *away* from it.
///
/// The two signs Wallhaven's `q` puts in front of a tag: `+` demands it, `-`
/// forbids it. A bare word is neither — Wallhaven treats it as a weak "should
/// match" — so the filter always signs its tags rather than leaning on that.
enum TagSense {
  /// `+tag`: every result must carry it.
  include('+'),

  /// `-tag`: no result may carry it.
  exclude('-');

  const TagSense(this.sign);

  /// The character `q` expects in front of the tag.
  final String sign;
}

/// One tag the user typed into the filter sheet, with the sense they gave it.
///
/// Deliberately *not* a `WallpaperTag`: that one carries an id and comes off a
/// wallpaper, and a tag chip on the detail screen follows it exactly via
/// `id:{n}`. This one is a name the user typed, so it can only ever be
/// Wallhaven's fuzzy `+name` / `-name` — a text match, which is what typing a
/// name means. It composes into `q` beside the free-text term rather than
/// rewriting it, so what the user types in the search box still reaches
/// Wallhaven untouched.
///
/// ```dart
/// const SearchTag('nature').token;                       // '+"nature"'
/// const SearchTag('people', TagSense.exclude).token;     // '-"people"'
/// ```
@immutable
final class SearchTag {
  /// Creates a tag constraint. Include is the default sense, because "show me
  /// this tag" is what adding one usually means.
  const SearchTag(this.name, [this.sense = TagSense.include]);

  /// The tag's name, as typed — no leading sign, and never empty (the sheet
  /// refuses a blank entry before it reaches here).
  final String name;

  /// Whether results must carry [name] or must not.
  final TagSense sense;

  /// The `q` fragment for this one tag, e.g. `+"nature"` or `-"people"`.
  ///
  /// Always quoted, even for a single word: confirmed live against Wallhaven
  /// (2026-07-15) that an *unquoted* multi-word name like `-anime girls`
  /// parses as `-anime` (exclude) plus a bare `girls` (weak "should match"),
  /// not as excluding the one tag — and two of those stacked can crush a
  /// listing to near zero. Quoting a single word costs nothing (`+"nature"`
  /// and `+nature` return identical results) so there is no case worth
  /// special-casing.
  String get token => '${sense.sign}"$name"';

  /// Returns a copy under the other [sense], for the toggle on a chip.
  SearchTag flipped() {
    final TagSense other = sense == TagSense.include
        ? TagSense.exclude
        : TagSense.include;
    return SearchTag(name, other);
  }

  /// Two tags are the same constraint when name *and* sense match: `+nature`
  /// and `-nature` are different filters on the same word, and both may sit in
  /// one query.
  @override
  bool operator ==(Object other) =>
      other is SearchTag && other.name == name && other.sense == sense;

  @override
  int get hashCode => Object.hash(name, sense);
}
