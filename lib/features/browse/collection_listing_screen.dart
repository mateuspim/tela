import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/domain/models/wallpaper_page.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/collection_purity_button.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The wallpapers inside one collection.
///
/// Pushed like `LinkedListingScreen`, and for the same reason: Back returns to
/// wherever the collection was opened from and the browse tabs are left alone.
///
/// **It offers purity and nothing else, and that is a hard constraint rather
/// than a simplification.** A collection's contents endpoint honours only
/// `purity`; `categories`, `atleast`, `ratios`, `sorting` and `order` are
/// accepted and silently ignored (measured live against Wallhaven 2026-08-26,
/// and stated in its own API reference). Showing the full filter sheet here
/// would render controls that quietly do nothing — the exact failure
/// `SourceFilter` exists to design out — so this screen has its own small
/// purity control instead of `BrowseFilterButton`.
///
/// A collection is also **hand-ordered by its owner**, so there is no sorting
/// to offer even if the endpoint took one.
class CollectionListingScreen extends ConsumerStatefulWidget {
  /// Creates the screen showing [collection]'s wallpapers.
  const CollectionListingScreen({
    required this.collection,
    this.seed,
    super.key,
  });

  /// The collection to show.
  final WallpaperCollection collection;

  /// The listing this was opened from, whose purity is inherited.
  ///
  /// Same rule as `LinkedListingScreen`: a sketchy session stays sketchy
  /// across a follow, rather than silently resetting to safe. Only the purity
  /// is taken — it is the only part this listing can honour.
  final SearchQuery? seed;

  @override
  ConsumerState<CollectionListingScreen> createState() =>
      _CollectionListingScreenState();
}

class _CollectionListingScreenState
    extends ConsumerState<CollectionListingScreen> {
  late PurityFilter _purity;

  /// The most recent page, kept only to report how much of the collection this
  /// user is actually being shown. See [_hiddenCount].
  WallpaperPage? _lastPage;

  @override
  void initState() {
    super.initState();
    // read, not watch: inheriting is a starting point, not a subscription.
    final SearchQuery seed = widget.seed ?? ref.read(browseQueryProvider);
    _purity = seed.purity;
  }

  /// How many of the collection's wallpapers this listing is not showing.
  ///
  /// Null until a page has landed. The number is real and worth printing:
  /// `WallpaperCollection.count` is the whole list, while a page's `total` is
  /// what survives the purity filter and the stored key — a collection of 82
  /// answers 0 under a safe filter (measured live). Without this the screen is
  /// an empty grid under a row that promised 82, with nothing to explain it.
  int? get _hiddenCount {
    final int? shown = _lastPage?.total;
    if (shown == null) return null;
    final int hidden = widget.collection.count - shown;
    return hidden > 0 ? hidden : null;
  }

  @override
  Widget build(BuildContext context) {
    // Purity is the only filter the endpoint honours, but the query still has
    // to carry the screen size: it is what the grid decodes tiles against.
    final SearchQuery query = SearchQuery(
      purity: _purity,
    ).forScreen(screenResolution(context));

    return SelectionShelfScope(
      child: Scaffold(
        appBar: GradientAppBar(
          title: _title(context),
          actions: <Widget>[
            const SelectModeButton(),
            CollectionPurityButton(
              purity: _purity,
              onChanged: (PurityFilter purity) =>
                  setState(() => _purity = purity),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: <Widget>[
            _HiddenNotice(hidden: _hiddenCount),
            Expanded(
              child: WallpaperGrid(
                query: query,
                galleryIdentity: 'collection:${widget.collection.ref.key}',
                // A collection is a nameable thing to file downloads under, and
                // its label is already the user's own word for it.
                listingFolder: TagFolder.sanitize(widget.collection.label),
                pageFetch: _fetchPage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pages straight off the collection, bypassing `SearchWallpapers` entirely.
  ///
  /// There is no query to build and no shuffle seed to carry: a collection is
  /// addressed by owner and id, and page N is page N.
  Future<WallpaperPage> _fetchPage(int page) async {
    final WallpaperPage fetched = await ref
        .read(browseCollectionsProvider)
        .page(widget.collection.ref, page: page, purity: _purity);
    if (mounted) {
      // Recorded outside setState: the grid is already rebuilding around this
      // page, and the notice above it can wait for that frame rather than
      // forcing a second one.
      _lastPage = fetched;
      scheduleMicrotask(() {
        if (mounted) setState(() {});
      });
    }
    return fetched;
  }

  /// Names the collection, then says whose it is — the same two-line shape
  /// `LinkedListingScreen` gives a tag or an uploader.
  Widget _title(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.collection.label, style: text.titleMedium),
        Text(
          '@${widget.collection.ref.owner}',
          style: text.labelSmall,
        ),
      ],
    );
  }
}

/// Says how much of the collection is being withheld, and never lies by
/// omission when the answer is "all of it".
class _HiddenNotice extends StatelessWidget {
  const _HiddenNotice({required this.hidden});

  final int? hidden;

  @override
  Widget build(BuildContext context) {
    final int? count = hidden;
    if (count == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.visibility_off_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).collectionHiddenByPurity(count),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
