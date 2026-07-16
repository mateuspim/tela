import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/features/browse/browse_filter_button.dart';
import 'package:tela/features/browse/linked_query_controller.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The listing behind a link followed from a wallpaper — a tag, or an uploader.
///
/// It is *pushed*, never a tab: Back returns to the wallpaper it was opened
/// from, and the browse tabs are left exactly as they were. So the term and the
/// sorting are the link's, while everything else is inherited from the listing
/// the user is already browsing under — their filters still apply here, as they
/// do on wallhaven.cc, and the grid is still fitted to the device's own screen.
///
/// Inherited, but not shared: from arrival the filters are this listing's own
/// (see [LinkedQueryController]), so narrowing a tag to look at it does not
/// narrow the Browse tabs waiting underneath. Back really does leave them as
/// they were.
class LinkedListingScreen extends ConsumerWidget {
  /// Creates the screen showing [link]'s wallpapers.
  const LinkedListingScreen({required this.link, super.key});

  /// What was followed to get here.
  final WallpaperLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String identity = _galleryIdentity;
    final SearchQuery filters = ref.watch(linkedQueryProvider(identity));
    // The term and the sorting are the link's, not the user's: this listing
    // *is* that tag, newest first. What the sheet writes survives the layering.
    final SearchQuery query = filters
        .copyWith(term: link.term, sorting: Sorting.dateAdded)
        .forScreen(screenResolution(context));

    return Scaffold(
      appBar: AppBar(
        title: _title(context),
        actions: <Widget>[
          BrowseFilterButton(
            filters: filters,
            scope: ref.read(linkedQueryProvider(identity).notifier),
          ),
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
  /// wanted to imply one.
  Widget _title(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(_name, style: text.titleMedium),
        Text(_kind(AppLocalizations.of(context)), style: text.labelSmall),
      ],
    );
  }

  String get _name => switch (link) {
    TagLink(:final WallpaperTag tag) => tag.name,
    UploaderLink(:final String username) => '@$username',
  };

  String get _galleryIdentity => switch (link) {
    TagLink(:final WallpaperTag tag) => 'linked:tag:${tag.id}',
    UploaderLink(:final String username) => 'linked:uploader:$username',
  };

  String _kind(AppLocalizations l10n) => switch (link) {
    TagLink() => l10n.listingTagged,
    UploaderLink() => l10n.listingUploads,
  };
}
