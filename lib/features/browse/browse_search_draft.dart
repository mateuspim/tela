import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// What is *typed* in the browse search field, before anything is submitted.
///
/// Deliberately not the same thing as `browseQueryProvider.term`, which is the
/// **committed** term the grids are showing. This is transient UI text that
/// changes on every keystroke and must never reach the network — search-as-you-
/// type would spend Wallhaven's 45 requests a minute on prefixes.
///
/// It exists because the id-jump chip and the field live in different subtrees:
/// the field is the app bar's title and the chip sits in the app bar's bottom,
/// so a private `TextEditingController` cannot reach both.
final NotifierProvider<BrowseSearchDraft, String> browseSearchDraftProvider =
    NotifierProvider<BrowseSearchDraft, String>(BrowseSearchDraft.new);

/// Holds the draft search text. See [browseSearchDraftProvider].
class BrowseSearchDraft extends Notifier<String> {
  @override
  String build() => '';

  /// What is currently typed. `state` itself is protected, so this is how a
  /// caller holding the notifier reads it back.
  String get typed => state;

  /// Records what is currently typed.
  set typed(String text) => state = text;
}

/// The active source's own id inside the draft text, or null if it isn't one.
///
/// Watched by the id-jump chip and nothing else. Keeping it that narrow is
/// what stops a keystroke from rebuilding the browse screen: the chip floats
/// over the grid, so only the chip is listening to this.
final Provider<String?> browseDraftWallpaperIdProvider = Provider<String?>((
  Ref ref,
) {
  final WallpaperSource source = ref.watch(activeWallpaperSourceProvider);
  return source.wallpaperIdIn(ref.watch(browseSearchDraftProvider));
});
