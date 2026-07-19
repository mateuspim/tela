import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/domain/models/download_record.dart';
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
    return SizedBox(
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
    );
  }

  /// One preview thumbnail, sized by its own aspect ratio at the band's height.
  ///
  /// It carries no missing-file badge, unlike the history grid's tile. That
  /// badge marks the difference between setting a file you have and paying for
  /// a re-download, and the history screen is where that difference changes
  /// what a tap costs — the same argument `downloadedIdsProvider` already makes
  /// for not subtracting `missingDownloadsProvider` on the browse wall.
  Widget _tile(BuildContext context, List<DownloadRecord> recent, int index) {
    final DownloadRecord download = recent[index];
    return SizedBox(
      width: stripHeight * download.wallpaper.resolution.aspectRatio,
      child: WallpaperTile(
        wallpaper: download.wallpaper,
        heroTag: shelfHeroTag(
          'library-downloads',
          download.wallpaper.id,
          index,
        ),
        onTap: () => openDownloadViewer(context, recent, index),
        // Everything here is downloaded by definition, so only the heart
        // carries information — the same narrowing the history shelf makes.
        visibleMarks: const <WallpaperMark>{WallpaperMark.favorited},
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        l10n.downloadHistoryEmpty,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
