import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';

/// Which tag the chooser offers first, and why that one.
///
/// The whole point of the feature is not having to type a tag: pick ten
/// wallpapers and the thing they have in common should already be selected. So
/// what is pinned here is the *ordering* — a suggestion list that put the
/// generic tag above the describing one would be worse than no list.
void main() {
  const SuggestTagFolders suggest = SuggestTagFolders();

  List<WallpaperTag> tags(List<String> names) => <WallpaperTag>[
    for (final String name in names) WallpaperTag(name: name),
  ];

  List<TagFolder> ranked({
    required Map<String, List<WallpaperTag>> carried,
    SearchQuery query = const SearchQuery(),
    Set<TagFolder> existing = const <TagFolder>{},
  }) {
    return suggest(
      tags: carried,
      selectionSize: carried.length,
      searched: searchTagIn(query),
      existing: existing,
    ).map((TagCandidate c) => c.tag).toList();
  }

  test('ranks by how much of the selection carries the tag', () {
    final List<TagFolder> offers = ranked(
      carried: <String, List<WallpaperTag>>{
        'a': tags(<String>['landscape', 'nature', 'mountains']),
        'b': tags(<String>['landscape', 'nature']),
        'c': tags(<String>['landscape']),
      },
    );

    expect(offers.map((TagFolder t) => t.name), <String>[
      'landscape',
      'nature',
      'mountains',
    ]);
  });

  test('reports the share so the chooser can show 8 of 10', () {
    final List<TagCandidate> offers = suggest(
      tags: <String, List<WallpaperTag>>{
        'a': tags(<String>['anime']),
        'b': tags(<String>['anime']),
        'c': tags(<String>['cars']),
      },
      selectionSize: 3,
      searched: null,
      existing: const <TagFolder>{},
    );

    expect(offers.first.tag, TagFolder('anime'));
    expect(offers.first.share, 2);
    expect(offers.first.origin, TagCandidateOrigin.selection);
  });

  group('the search that is already the answer', () {
    /// Downloading a whole `+"cyberpunk"` listing means these wallpapers *are*
    /// the cyberpunk ones — a stronger claim than any count, and free.
    test('an included search tag outranks the most-shared tag', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['neon', 'city']),
          'b': tags(<String>['neon', 'city']),
        },
        query: const SearchQuery(tags: <SearchTag>[SearchTag('cyberpunk')]),
      );

      expect(offers.first, TagFolder('cyberpunk'));
    });

    test('a bare search term counts as one', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['neon']),
        },
        query: const SearchQuery(term: 'cyberpunk'),
      );

      expect(offers.first, TagFolder('cyberpunk'));
    });

    /// `-"anime"` says the results are *not* that. Filing them under it would
    /// be exactly backwards.
    test('an excluded tag is never suggested', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['neon']),
        },
        query: const SearchQuery(
          tags: <SearchTag>[SearchTag('anime', TagSense.exclude)],
        ),
      );

      expect(offers, isNot(contains(TagFolder('anime'))));
      expect(offers.first, TagFolder('neon'));
    });

    test('the search tag is not repeated among the counted ones', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['cyberpunk']),
          'b': tags(<String>['cyberpunk']),
        },
        query: const SearchQuery(tags: <SearchTag>[SearchTag('cyberpunk')]),
      );

      expect(offers, <TagFolder>[TagFolder('cyberpunk')]);
    });
  });

  group('folders that already exist', () {
    /// So a library fills the folders it has instead of sprouting
    /// near-duplicates beside them.
    test('win a tie on share', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['aaa', 'zzz']),
        },
        existing: <TagFolder>{TagFolder('zzz')},
      );

      expect(offers.map((TagFolder t) => t.name), <String>['zzz', 'aaa']);
    });

    /// Reachable in one tap, but never in front of a tag that actually
    /// describes what is being downloaded.
    test('are offered last when nothing in the selection mentions them', () {
      final List<TagCandidate> offers = suggest(
        tags: <String, List<WallpaperTag>>{
          'a': tags(<String>['neon']),
        },
        selectionSize: 1,
        searched: null,
        existing: <TagFolder>{TagFolder('archive')},
      );

      expect(offers.map((TagCandidate c) => c.tag.name), <String>[
        'neon',
        'archive',
      ]);
      expect(offers.last.origin, TagCandidateOrigin.existingFolder);
    });

    test('are not repeated when the selection does mention them', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['neon']),
        },
        existing: <TagFolder>{TagFolder('neon')},
      );

      expect(offers, <TagFolder>[TagFolder('neon')]);
    });
  });

  group('a source tag is not a folder name', () {
    test('names are sanitized before they are counted', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['long  hair']),
          'b': tags(<String>['long hair']),
        },
      );

      expect(offers, <TagFolder>[TagFolder('long hair')]);
    });

    test('a tag that cannot be a folder is dropped, not mangled', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          'a': tags(<String>['>_<', '...', 'neon']),
        },
      );

      expect(offers, <TagFolder>[TagFolder('neon')]);
    });

    /// Two of one wallpaper's tags collapsing to one folder must not let it
    /// vote twice for that folder.
    test('one wallpaper counts once per folder', () {
      final List<TagCandidate> offers = suggest(
        tags: <String, List<WallpaperTag>>{
          'a': tags(<String>['sci fi', 'sci  fi']),
        },
        selectionSize: 1,
        searched: null,
        existing: const <TagFolder>{},
      );

      expect(offers.single.share, 1);
    });
  });

  /// A chooser whose chips reorder between two identical selections is one
  /// nobody can learn to use.
  test('equal candidates come back in a stable, alphabetical order', () {
    final List<TagFolder> once = ranked(
      carried: <String, List<WallpaperTag>>{
        'a': tags(<String>['beta', 'alpha', 'gamma']),
      },
    );
    final List<TagFolder> twice = ranked(
      carried: <String, List<WallpaperTag>>{
        'a': tags(<String>['gamma', 'beta', 'alpha']),
      },
    );

    expect(once.map((TagFolder t) => t.name), <String>[
      'alpha',
      'beta',
      'gamma',
    ]);
    expect(twice, once);
  });

  test('an empty lookup answers with the folders there are', () {
    final List<TagFolder> offers = ranked(
      carried: const <String, List<WallpaperTag>>{},
      existing: <TagFolder>{TagFolder('archive')},
    );

    expect(offers, <TagFolder>[TagFolder('archive')]);
  });

  test('nothing at all is an empty list, not a crash', () {
    expect(ranked(carried: const <String, List<WallpaperTag>>{}), isEmpty);
  });

  group('how many are offered', () {
    /// A booru selection carries hundreds of distinct tags between it — artist,
    /// series, character, colour, every visual attribute. Offering all of them
    /// is a wall of chips to read instead of an answer (owner, 2026-08-12:
    /// "that brought a lot of tags, i only want to show fewer").
    test('caps the counted tags at ten, keeping the most shared', () {
      final List<TagFolder> offers = ranked(
        carried: <String, List<WallpaperTag>>{
          for (int i = 0; i < 30; i++) 'w$i': tags(<String>['tag$i', 'shared']),
        },
      );

      // `shared` is itself one of the counted ten, not an extra on top.
      expect(offers.length, SuggestTagFolders.maxSuggestions);
      expect(offers.first, TagFolder('shared'));
    });

    /// The search's tag and the folders that exist are not guesses about the
    /// selection, so they do not compete with the counted ones for that space.
    test('the search tag and existing folders sit outside the cap', () {
      final List<TagCandidate> offers = suggest(
        tags: <String, List<WallpaperTag>>{
          for (int i = 0; i < 30; i++) 'w$i': tags(<String>['tag$i']),
        },
        selectionSize: 30,
        searched: TagFolder('cyberpunk'),
        existing: <TagFolder>{TagFolder('archive')},
      );

      expect(offers.first.tag, TagFolder('cyberpunk'));
      expect(offers.last.tag, TagFolder('archive'));
      expect(offers.length, SuggestTagFolders.maxSuggestions + 2);
    });
  });
}
