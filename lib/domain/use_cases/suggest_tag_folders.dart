import 'package:meta/meta.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

/// The tag a listing is searching for, or null when it is not a tag search.
///
/// **Free, and deliberately reachable without the ranking.** Every other
/// candidate needs `WallpaperSource.tagsFor`, which on Wallhaven is a request
/// per wallpaper — but this one is already on screen. It is what makes
/// "I am looking at Leo (artist) and I want these filed under it" cost nothing
/// and appear the instant the chooser opens, rather than after a lookup it does
/// not need.
///
/// An **included** tag only: `-"anime"` says these wallpapers are *not* that,
/// and filing them under it would be exactly backwards. A bare search term
/// counts when it survives sanitizing as one — typing `cyberpunk` into the box
/// and downloading the results means the same thing the chip does.
TagFolder? searchTagIn(SearchQuery query) {
  for (final SearchTag tag in query.tags) {
    if (tag.sense != TagSense.include) continue;
    final TagFolder? folder = TagFolder.sanitize(tag.name);
    if (folder != null) return folder;
  }
  return TagFolder.sanitize(query.term);
}

/// Where a suggested tag came from, which is also why it is ranked where it is.
enum TagCandidateOrigin {
  /// The listing being downloaded from is a search for this tag. Downloading a
  /// whole `+"cyberpunk"` page means these wallpapers *are* the cyberpunk ones,
  /// which is a stronger claim about the selection than any count.
  search,

  /// Some of the selected wallpapers carry it, according to their own source.
  selection,

  /// It is already a folder, and nothing in this selection mentions it.
  existingFolder,
}

/// One tag the chooser can offer, and how well it describes the selection.
@immutable
class TagCandidate {
  /// Creates a candidate carried by [share] of the selection.
  const TagCandidate({
    required this.tag,
    required this.origin,
    this.share = 0,
  });

  /// The folder this would file the download under.
  final TagFolder tag;

  /// Why it is being offered.
  final TagCandidateOrigin origin;

  /// How many of the selected wallpapers carry it — the `8` in `8/10`. Zero
  /// for a candidate that came from the search or from an existing folder,
  /// where the count would be a number about nothing.
  final int share;

  @override
  bool operator ==(Object other) =>
      other is TagCandidate &&
      other.tag == tag &&
      other.origin == origin &&
      other.share == share;

  @override
  int get hashCode => Object.hash(tag, origin, share);

  @override
  String toString() => 'TagCandidate($tag, ${origin.name}, $share)';
}

/// Turns what a selection *is* into the tags it could be filed under.
///
/// The chooser's answer to "don't make me type it": select ten wallpapers and
/// the tags they have in common are right there, best first. Pure Dart — no
/// network, no Flutter — because the ranking is the part worth pinning, and the
/// fetching that feeds it belongs to `WallpaperSource.tagsFor`, where the cost
/// lives.
///
/// **A source's tag is not a folder name.** Wallhaven and Konachan admit
/// characters a directory cannot hold, so every candidate goes through
/// [TagFolder.sanitize] and one that leaves nothing legal is dropped rather
/// than mangled into a near-duplicate of a folder the user already has.
///
/// ```dart
/// final List<TagCandidate> offers = suggestTagFolders(
///   tags: fetched,
///   selectionSize: 10,
///   searched: ListingOrigin.folderOf(context),
///   existing: knownTags,
/// );
/// ```
class SuggestTagFolders {
  /// Creates the ranking. Stateless — it is a function with a name.
  const SuggestTagFolders();

  /// How many counted tags the chooser offers. The search's own tag and the
  /// existing folders are on top of this — neither is a guess about the
  /// selection, so neither competes for the same space.
  static const int maxSuggestions = 10;

  /// Ranks the tags [tags] reports for a selection of [selectionSize].
  ///
  /// The order, and the reasoning for each step:
  ///
  /// 1. **The search's own tag first**, when the listing has one. It costs no
  ///    request, and "download this whole tag" is the case where the right
  ///    answer is already on screen — so it is also what the chooser starts on.
  /// 2. **Then by how much of the selection carries it.** The tag ten out of
  ///    ten share describes them better than the one six do; that is the whole
  ///    meaning of "best".
  /// 3. **Ties go to a folder that already exists**, so a library fills its
  ///    folders instead of sprouting near-duplicates beside them.
  /// 4. **Then alphabetically**, so the list is stable — a chooser whose chips
  ///    reorder between two identical selections is one nobody can learn.
  ///
  /// [searched] is that first candidate, and it is **passed in rather than
  /// read back out of a query**. A followed tag listing searches on `id:37`,
  /// so a query cannot always say what it is a listing *of* — only the screen
  /// that followed the link can. `ListingOrigin.folderOf` is the one place
  /// that decision is made; [searchTagIn] is the half of it a query can answer.
  ///
  /// [existing] folders that nothing in the selection mentions are appended
  /// last: still reachable in one tap, never in front of a tag that actually
  /// describes what is being downloaded.
  ///
  /// The list is capped at [maxSuggestions] of the counted ones. A booru
  /// selection carries *hundreds* of distinct tags between it — artist, series,
  /// character, colour, every visual attribute — and a chooser that offered all
  /// of them would be a wall of chips to read instead of an answer. The ones
  /// dropped are, by construction, the ones fewest of the selection share.
  List<TagCandidate> call({
    required Map<String, List<WallpaperTag>> tags,
    required int selectionSize,
    required TagFolder? searched,
    required Set<TagFolder> existing,
  }) {
    // The search's tag is offered from the front, so it must not also appear
    // among the counted ones — the same tag twice reads as two folders.
    final Map<TagFolder, int> shares = _shares(tags)..remove(searched);
    final List<TagCandidate> fromSelection = <TagCandidate>[
      for (final MapEntry<TagFolder, int> e in shares.entries)
        TagCandidate(
          tag: e.key,
          origin: TagCandidateOrigin.selection,
          share: e.value,
        ),
    ]..sort((TagCandidate a, TagCandidate b) => _rank(a, b, existing));
    return <TagCandidate>[
      if (searched != null)
        TagCandidate(tag: searched, origin: TagCandidateOrigin.search),
      ...fromSelection.take(maxSuggestions),
      for (final TagFolder folder in _unmentioned(existing, shares, searched))
        TagCandidate(
          tag: folder,
          origin: TagCandidateOrigin.existingFolder,
        ),
    ];
  }

  /// How many wallpapers carry each tag, once names are folder-legal.
  ///
  /// Sanitizing before counting is what merges `long hair` and `long  hair`
  /// into one candidate rather than two chips for one folder.
  Map<TagFolder, int> _shares(Map<String, List<WallpaperTag>> tags) {
    final Map<TagFolder, int> shares = <TagFolder, int>{};
    for (final List<WallpaperTag> carried in tags.values) {
      for (final TagFolder folder in _foldersIn(carried)) {
        shares[folder] = (shares[folder] ?? 0) + 1;
      }
    }
    return shares;
  }

  /// One wallpaper's tags as folders, deduplicated — a wallpaper carrying two
  /// tags that sanitize alike must not count itself twice.
  Set<TagFolder> _foldersIn(List<WallpaperTag> carried) {
    return <TagFolder>{
      for (final WallpaperTag tag in carried) ?TagFolder.sanitize(tag.name),
    };
  }

  /// Existing folders no selected wallpaper mentions, alphabetically.
  List<TagFolder> _unmentioned(
    Set<TagFolder> existing,
    Map<TagFolder, int> shares,
    TagFolder? searched,
  ) {
    return existing
        .where((TagFolder f) => !shares.containsKey(f) && f != searched)
        .toList()
      ..sort(_byName);
  }

  int _rank(TagCandidate a, TagCandidate b, Set<TagFolder> existing) {
    if (a.share != b.share) return b.share.compareTo(a.share);
    final bool aKnown = existing.contains(a.tag);
    if (aKnown != existing.contains(b.tag)) return aKnown ? -1 : 1;
    return _byName(a.tag, b.tag);
  }

  int _byName(TagFolder a, TagFolder b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
