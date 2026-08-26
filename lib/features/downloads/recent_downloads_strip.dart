import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/selectable_wallpaper_shelf.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/download_viewer_launch.dart';

/// A horizontal preview of the newest downloads, for the Library hub.
///
/// The thumbnails *are* the way in: tapping one opens the same local-first
/// viewer the history grid opens ([openDownloadViewer]), positioned on it. So
/// this replaced the text row that used to sit here rather than joining it —
/// a row and a strip both meaning "downloads" is two affordances for one idea,
/// and the strip is the one that also answers "what have I got?".
///
/// Deliberately **not** density-aware. The wall's tile density is a statement
/// about a shelf you browse; this is a fixed-height preview band whose job is
/// to stay out of the way of the favorites shelf below it, and a *Large*
/// setting turning the hub into two enormous strips would defeat that.
///
/// The private tier cannot appear here: [recentDownloadsProvider] excludes
/// explicit downloads, which is load-bearing exactly as it is for C4's tile
/// marks — the hub sits behind no app-lock.
class RecentDownloadsStrip extends ConsumerWidget {
  /// Creates the preview strip.
  const RecentDownloadsStrip({super.key});

  /// Height of the preview band, in dips.
  ///
  /// Fixed, and small enough that the strip reads as a glance rather than as a
  /// second wall — the favorites shelf below is the screen's subject.
  static const double stripHeight = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // A failed or in-flight read draws the empty line rather than an error or a
    // spinner: this is a preview band above the real content, and a hub that
    // will not render because a local listing hiccuped is a worse screen than
    // one that momentarily says it is empty.
    final List<DownloadRecord> recent =
        ref.watch(recentDownloadsProvider).value ?? const <DownloadRecord>[];
    if (recent.isEmpty) return _empty(context, l10n);
    return SelectableWallpaperShelf(
      wallpapers: <Wallpaper>[
        for (final DownloadRecord record in recent) record.wallpaper,
      ],
      // The same pair the history grid offers, because it is the same shelf
      // seen through a smaller window — reaching *See all* first, only to make
      // the identical selection there, is the trip this exists to save.
      actions: const <WallpaperBatchAction>[
        WallpaperBatchAction.favorite,
        WallpaperBatchAction.beam,
        WallpaperBatchAction.forget,
      ],
      // The band is a fixed height inside the hub's unbounded column, so the
      // bar stacks above it rather than taking flex that is not there.
      expandChild: false,
      child: SizedBox(
        height: stripHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: recent.length,
          separatorBuilder: (BuildContext context, int _) =>
              const SizedBox(width: 12),
          itemBuilder: (BuildContext context, int index) =>
              _tile(context, recent, index),
        ),
      ),
    );
  }

  /// One preview thumbnail, sized by its own aspect ratio at the band's height.
  ///
  /// It carries no missing-file badge, unlike the history grid's tile. That
  /// badge marks the difference between setting a file you have and paying for
  /// a re-download, and the history screen is where that difference changes
  /// what a tap costs — the same argument `downloadedKeysProvider` already
  /// makes
  /// for not subtracting `missingDownloadsProvider` on the browse wall.
  Widget _tile(BuildContext context, List<DownloadRecord> recent, int index) {
    final DownloadRecord download = recent[index];
    final gestures = selectableTileGestures(
      context: context,
      wallpaperKey: download.wallpaper.ref.key,
      onOpen: () => openDownloadViewer(context, recent, index),
      // The same rule every library shelf follows, and the reason this strip
      // needed it: without a long press here the only way to batch your
      // downloads was to reach *See all* first, while the favorites shelf a
      // few dips below selected in place (owner, 2026-07-19).
      longPressSelects: true,
    );
    return SizedBox(
      width: stripHeight * download.wallpaper.resolution.aspectRatio,
      child: WallpaperTile(
        wallpaper: download.wallpaper,
        heroTag: shelfHeroTag(
          'library-downloads',
          download.wallpaper.ref.key,
          index,
        ),
        onTap: gestures.onTap,
        onLongPress: gestures.onLongPress,
        // Everything here is downloaded by definition, so only the heart
        // carries information — the same narrowing the history shelf makes.
        visibleMarks: const <WallpaperMark>{WallpaperMark.favorited},
        // Recent downloads can be from either source; name each one.
        showSourceBadge: true,
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l10n) {
    // Left-aligned at the same 16 as the header and the thumbnail row, and
    // capped: centred full-width text stranded the line across a 2560-wide
    // panel and read as detached from the section it belongs to.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            l10n.downloadHistoryEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
