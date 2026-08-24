import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';

import '../fakes/fake_wallpaper_source.dart';

/// What a tag suggestion costs before the chooser can show it.
///
/// The rule that matters is the one the owner hit on the device (2026-08-12):
/// browsing a tag and selecting a hundred wallpapers should not spend a request
/// per wallpaper rediscovering the word already in the search box.
void main() {
  late FakeWallpaperSource source;

  List<Wallpaper> selection(int count) => <Wallpaper>[
    for (int i = 0; i < count; i++) _wallpaper('w$i'),
  ];

  setUp(() {
    source = FakeWallpaperSource()
      ..tagsById = <String, List<WallpaperTag>>{
        for (int i = 0; i < 200; i++)
          'w$i': const <WallpaperTag>[WallpaperTag(name: 'landscape')],
      };
  });

  /// The listing already answered it. A lookup could add nothing worth a
  /// request per wallpaper.
  test('spends nothing when the listing is already a tag search', () async {
    final List<TagCandidate> offers = await suggestedTagsFor(
      source: source,
      listingTag: TagFolder.sanitize('Leo (artist)'),
      known: const <TagFolder>[],
      selection: selection(100),
    );

    expect(source.tagBudgets, isEmpty, reason: 'a lookup was started');
    expect(offers.single.tag, TagFolder('Leo artist'));
    expect(offers.single.origin, TagCandidateOrigin.search);
  });

  test('spends nothing for a bare search term either', () async {
    await suggestedTagsFor(
      source: source,
      listingTag: TagFolder.sanitize('cyberpunk'),
      known: const <TagFolder>[],
      selection: selection(100),
    );

    expect(source.tagBudgets, isEmpty);
  });

  test('looks the tags up when the listing names none', () async {
    final List<TagCandidate> offers = await suggestedTagsFor(
      source: source,
      listingTag: null,
      known: const <TagFolder>[],
      selection: selection(3),
    );

    expect(source.tagBudgets, <int>[tagSuggestionBudget]);
    expect(offers.single.tag, TagFolder('landscape'));
  });

  /// **The count has to describe the sample.** The budget stops the lookup at
  /// 25, so a 30-wallpaper selection is read 25 deep — and reporting "25/30"
  /// would claim five of them lack a tag nobody ever looked for.
  test('counts against what was examined, not what was selected', () async {
    final List<TagCandidate> offers = await suggestedTagsFor(
      source: source,
      listingTag: null,
      known: const <TagFolder>[],
      selection: selection(30),
    );

    expect(offers.single.share, tagSuggestionBudget);
  });

  test('an empty selection asks nothing', () async {
    final List<TagCandidate> offers = await suggestedTagsFor(
      source: source,
      listingTag: null,
      known: const <TagFolder>[],
      selection: const <Wallpaper>[],
    );

    expect(offers, isEmpty);
    expect(source.tagBudgets, isEmpty);
  });
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  source: SourceId.wallhaven,
  pageUrl: Uri.parse('https://wallhaven.cc/w/$id'),
  fullImageUrl: 'https://w.wallhaven.cc/full/xx/wallhaven-$id.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/xx/$id.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/xx/$id.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/xx/$id.jpg',
  resolution: const Resolution(1440, 3200),
  fileSizeBytes: 2048,
  purity: Purity.sfw,
  category: Category.general,
  colors: const <String>[],
);
