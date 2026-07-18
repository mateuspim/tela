import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/core/ui/wallpaper_swatch.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/features/browse/browse_filter_button.dart';
import 'package:tela/features/browse/browse_filter_scope.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The listing behind a link followed from a wallpaper — a tag, or an uploader.
///
/// It is *pushed*, never a tab: Back returns to the wallpaper it was opened
/// from, and the browse tabs are left exactly as they were. So the term and the
/// sorting are the link's, while everything else is inherited from the listing
/// the user is already browsing under — their filters still apply here, as they
/// do on wallhaven.cc, and the grid is still fitted to the device's own screen.
///
/// **Where the filters come from is [seed].** Followed from a wallpaper the
/// user reached mid-browse, [seed] is that listing's own query, so a sketchy
/// session stays sketchy across a tag→wallpaper→tag chain — the bug this fixes,
/// where every follow silently reset to Browse's global filters and dropped the
/// purity the user was actually browsing under. Null (a curated shelf, a deep
/// link) falls back to Browse, the same starting point arriving from Browse
/// gives.
///
/// Inherited, but not shared: the filters are this screen's own state from
/// arrival, so narrowing a tag to look at it does not narrow the Browse tabs
/// waiting underneath, and leaving really does leave them as they were. Two
/// listings reached one after another never inherit each other's narrowing —
/// each is its own widget, seeded from where *it* was followed from.
class LinkedListingScreen extends ConsumerStatefulWidget {
  /// Creates the screen showing [link]'s wallpapers under [seed]'s filters.
  const LinkedListingScreen({required this.link, this.seed, super.key});

  /// What was followed to get here.
  final WallpaperLink link;

  /// The filters to open under, or null to fall back to Browse's own.
  final SearchQuery? seed;

  @override
  ConsumerState<LinkedListingScreen> createState() =>
      _LinkedListingScreenState();
}

/// The filter state is the screen's own, edited in place by the shared filter
/// sheet through [BrowseFilterScope] — the same interface Browse answers, over
/// local state instead of a global provider, because a pushed listing's filters
/// are transient and belong to nobody else.
class _LinkedListingScreenState extends ConsumerState<LinkedListingScreen>
    implements BrowseFilterScope {
  late SearchQuery _filters;

  @override
  void initState() {
    super.initState();
    // read, not watch: inheriting is a starting point, not a subscription. A
    // later change to Browse's own filters must not reach in and re-narrow a
    // listing the user has since filtered by hand.
    _filters = widget.seed ?? ref.read(browseQueryProvider);
  }

  @override
  SearchQuery get filters => _filters;

  @override
  void applyFilters(SearchQuery filters) => setState(() => _filters = filters);

  /// Resets to the same defaults Browse resets to — **including purity back to
  /// safe**. Re-inheriting the seed here would be the obvious shortcut and the
  /// wrong one: it would leave a sketchy session sketchy, and ending one is
  /// this button's whole job.
  @override
  void clearFilters() => setState(() {
    _filters = ref.read(browseQueryProvider.notifier).defaultQuery;
  });

  @override
  Widget build(BuildContext context) {
    final String identity = _galleryIdentity;
    // The link narrows the query — its term or its colour, always newest first;
    // the rest is the user's, and what the sheet writes survives the layering.
    final SearchQuery query = widget.link
        .narrow(_filters)
        .forScreen(screenResolution(context));

    return Scaffold(
      appBar: GradientAppBar(
        title: _title(context),
        actions: <Widget>[
          BrowseFilterButton(filters: _filters, scope: this),
          const SizedBox(width: 8),
        ],
      ),
      body: WallpaperGrid(query: query, galleryIdentity: identity),
    );
  }

  /// Names the link, and then says what kind of listing this is.
  ///
  /// The second line is not decoration: an uploader's listing is their
  /// *uploads*, and Wallhaven's API has no profile to show even if the screen
  /// wanted to imply one. A colour has no name to print, so its swatch stands
  /// in for one beside the same kind of caption.
  Widget _title(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (widget.link) {
      TagLink(:final WallpaperTag tag) => _captioned(
        tag.name,
        l10n.listingTagged,
        text,
      ),
      UploaderLink(:final String username) => _captioned(
        '@$username',
        l10n.listingUploads,
        text,
      ),
      ColorLink(:final WallpaperColor color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WallpaperSwatch(color: color),
          const SizedBox(width: 12),
          Text(l10n.listingColored, style: text.titleMedium),
        ],
      ),
    };
  }

  Widget _captioned(String name, String kind, TextTheme text) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(name, style: text.titleMedium),
      Text(kind, style: text.labelSmall),
    ],
  );

  String get _galleryIdentity => switch (widget.link) {
    TagLink(:final WallpaperTag tag) => 'linked:tag:${tag.id}',
    UploaderLink(:final String username) => 'linked:uploader:$username',
    ColorLink(:final WallpaperColor color) =>
      'linked:color:${color.toApiValue()}',
  };
}
