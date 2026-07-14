import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/screen_resolution.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/features/browse/browse_query_controller.dart';
import 'package:tela/features/browse/wallpaper_grid.dart';

/// The listing behind a link followed from a wallpaper — a tag, or an uploader.
///
/// It is *pushed*, never a tab: Back returns to the wallpaper it was opened
/// from, and the browse tabs are left exactly as they were. So the term and the
/// sorting are the link's, while everything else is inherited from the listing
/// the user is already browsing under — their filters still apply here, as they
/// do on wallhaven.cc, and the grid is still fitted to the device's own screen.
class LinkedListingScreen extends ConsumerWidget {
  /// Creates the screen showing [link]'s wallpapers.
  const LinkedListingScreen({required this.link, super.key});

  /// What was followed to get here.
  final WallpaperLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SearchQuery query = ref
        .watch(browseQueryProvider)
        .copyWith(term: link.term, sorting: Sorting.dateAdded)
        .forScreen(screenResolution(context));

    return Scaffold(
      appBar: AppBar(title: _title(context)),
      body: WallpaperGrid(query: query),
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

  String _kind(AppLocalizations l10n) => switch (link) {
    TagLink() => l10n.listingTagged,
    UploaderLink() => l10n.listingUploads,
  };
}
