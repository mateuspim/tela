import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/selectable_wallpaper_shelf.dart';
import 'package:tela/app/wallpaper_batch_actions.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/tag_filter_bar.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_marks_scope.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/queued_download.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/browse/wallpaper_tile.dart';
import 'package:tela/features/downloads/download_queue_tab.dart';
import 'package:tela/features/downloads/download_viewer_launch.dart';
import 'package:tela/features/downloads/missing_downloads_cleanup_button.dart';

/// The wallpapers already on this device, each one tap away from being set.
///
/// Tapping a tile now opens the immersive, local-first viewer at that exact
/// record — the same first-class fullscreen experience as Browse — with target
/// selection moved behind the viewer's Set action.
///
/// A long press now enters multi-select rather than offering to forget the one
/// row (D4). Forgetting is still here, and still confirms in the same words —
/// it is the batch action at a count of one, since "remove from history" and
/// "delete the file" are two different things and this tile looks exactly like
/// a file.
///
/// Two tabs now: **History**, the wallpapers that landed, and **Queue**, the
/// ones still owed. They belong on one screen because they are one idea seen
/// from either end — a queue entry becomes a history row — and because a
/// download that failed is one tap from the shelf it was headed for.
class DownloadHistoryScreen extends ConsumerWidget {
  /// Creates the download-history screen, optionally opening on one [tag].
  const DownloadHistoryScreen({this.tag, super.key});

  /// The tag to narrow to on open, or null to show everything.
  ///
  /// Set when the Library hub's tag row is tapped, which promises a shelf that
  /// is already filtered. The chips stay live afterwards — this is where the
  /// screen starts, not where it is stuck.
  final TagFolder? tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: SelectionShelfScope(
        child: Scaffold(
          appBar: GradientAppBar(
            toolbarHeight: 72,
            title: Text(
              l10n.downloadHistoryTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            actions: const <Widget>[
              MissingDownloadsCleanupButton(),
              SelectModeButton(),
              SizedBox(width: 8),
            ],
            bottom: TabBar(
              tabs: <Widget>[
                Tab(text: l10n.downloadHistoryTab),
                Tab(child: _queueTabLabel(context, ref, l10n)),
              ],
            ),
          ),
          body: TabBarView(
            children: <Widget>[
              _historyTab(context, ref, l10n),
              const DownloadQueueTab(),
            ],
          ),
        ),
      ),
    );
  }

  /// The Queue tab's label, badged while anything is owed.
  ///
  /// The badge is the whole reason the queue is reachable at all without
  /// looking for it: a batch draining behind the History tab is otherwise
  /// invisible, which is the state this feature exists to end.
  Widget _queueTabLabel(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final List<QueuedDownload> entries =
        ref.watch(downloadQueueControllerProvider).value ??
        const <QueuedDownload>[];
    final Text label = Text(l10n.downloadQueueTab);
    if (entries.isEmpty) return label;
    return Badge.count(count: entries.length, child: label);
  }

  Widget _historyTab(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final AsyncValue<List<DownloadRecord>> downloads = ref.watch(
      recentDownloadsProvider,
    );
    return downloads.when(
      data: (List<DownloadRecord> recent) => _TaggedHistory(
        openOn: tag,
        recent: recent,
        buildGrid: (List<DownloadRecord> shown) =>
            _grid(context, ref, l10n, shown),
      ),
      loading: () => const WallpaperGridSkeleton(),
      error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
        icon: Icons.error_outline,
        message: l10n.errorUnexpected,
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<DownloadRecord> recent,
  ) {
    if (recent.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.download_outlined,
        message: l10n.downloadHistoryEmpty,
      );
    }
    return SelectableWallpaperShelf(
      wallpapers: <Wallpaper>[
        for (final DownloadRecord record in recent) record.wallpaper,
      ],
      // The mirror of this shelf's marks again: everything here is downloaded,
      // so re-downloading is the one batch that says nothing. The two
      // destructive batches sit side by side and mean different things: forget
      // drops the list rows and leaves the files; delete removes both. Each
      // confirms, in its own words, through `runWallpaperBatchAction`.
      actions: const <WallpaperBatchAction>[
        WallpaperBatchAction.favorite,
        // Before the three that take something away: refiling is the
        // non-destructive answer to "this is in the wrong place", and it is the
        // one a user reaches for most while tidying.
        WallpaperBatchAction.retag,
        // Moving sits between the two destructive ones on purpose: it is the
        // middle answer to "I do not want this here" — the file stays, it just
        // stops being in Photos and in this list.
        WallpaperBatchAction.moveToPrivate,
        WallpaperBatchAction.forget,
        WallpaperBatchAction.delete,
      ],
      child: JustifiedWallpaperGrid(
        itemCount: recent.length,
        aspectRatioOf: (int index) =>
            recent[index].wallpaper.resolution.aspectRatio,
        itemBuilder: (BuildContext context, int index, double _, double _) =>
            _tile(context, ref, l10n, recent, index),
      ),
    );
  }

  /// One download, badged when its file is no longer on the device.
  ///
  /// The badge is not a warning that something is broken — the tile still works
  /// — it is the difference between "set this from the file you already have"
  /// and "re-download six megabytes first". Those are different actions and the
  /// grid should not present them identically. The badge simply does not appear
  /// while the probe is in flight, or if it fails: an unbadged tile is the
  /// status quo, and a history that will not render because a file check hung
  /// would be a worse screen than one that under-warns.
  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<DownloadRecord> recent,
    int index,
  ) {
    final DownloadRecord download = recent[index];
    final Set<String> missing =
        ref.watch(missingDownloadsProvider).value ?? const <String>{};
    final bool isMissing = missing.contains(download.wallpaper.ref.key);
    final gestures = selectableTileGestures(
      context: context,
      wallpaperKey: download.wallpaper.ref.key,
      onOpen: () => openDownloadViewer(context, recent, index),
      // Forgetting one row is now the batch forget at a count of one — the
      // plural strings render the identical sentence there, so the wording
      // that is the feature survives intact — which frees this gesture for the
      // same "long press means select" rule the favorites shelf follows.
      longPressSelects: true,
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: isMissing
          ? l10n.downloadHistoryRedownload(download.wallpaper.id)
          : l10n.downloadHistorySetAgain(download.wallpaper.id),
      // Expand, not the default loose fit: the grid hands this tile a cell of a
      // chosen width and height, and a loose Stack would let the WallpaperTile
      // fall back to its own intrinsic size and sit top-left inside the cell.
      // Invisible while cells are wall-sized, but a lone download gets a cell
      // blown up to two thirds of the viewport, where the un-expanded tile drew
      // small and adrift (the "lone history tile" anomaly). Favorites never hit
      // this because it puts the tile straight in the SizedBox, with no Stack.
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Opacity(
            opacity: isMissing ? 0.55 : 1,
            child: WallpaperTile(
              wallpaper: download.wallpaper,
              heroTag: shelfHeroTag(
                'download-history',
                download.wallpaper.ref.key,
                index,
              ),
              onTap: gestures.onTap,
              onLongPress: gestures.onLongPress,
              // The mirror of Favorites: everything here is downloaded by
              // definition, so only the heart carries information. It also
              // keeps this shelf to one new mark beside the missing badge.
              visibleMarks: const <WallpaperMark>{WallpaperMark.favorited},
              // The history spans every source downloaded from, so each tile
              // names its own — the badge sits bottom-left, clear of the
              // missing badge this screen adds top-right.
              showSourceBadge: true,
            ),
          ),
          if (isMissing)
            Positioned(top: 8, right: 8, child: _missingBadge(context, l10n)),
        ],
      ),
    );
  }

  /// Says "this one comes from Wallhaven now", in the one word a badge has.
  Widget _missingBadge(BuildContext context, AppLocalizations l10n) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.downloadHistoryFileGone,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.cloud_download_outlined,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The history grid with its tag filter above it.
///
/// Stateful only for the chip that is selected — the rows themselves stay in
/// `recentDownloadsProvider`, so a download landing while a filter is on still
/// re-renders through the same path it always did.
class _TaggedHistory extends StatefulWidget {
  const _TaggedHistory({
    required this.recent,
    required this.buildGrid,
    this.openOn,
  });

  /// The tag to start narrowed to, or null for everything.
  final TagFolder? openOn;

  /// Every recorded download, unfiltered.
  final List<DownloadRecord> recent;

  /// Renders the grid over whatever survives the filter.
  final Widget Function(List<DownloadRecord>) buildGrid;

  @override
  State<_TaggedHistory> createState() => _TaggedHistoryState();
}

class _TaggedHistoryState extends State<_TaggedHistory> {
  late TagFilter _filter = widget.openOn == null
      ? const TagFilter.all()
      : TagFilter.of(widget.openOn!);

  @override
  Widget build(BuildContext context) {
    final List<DownloadRecord> shown = widget.recent
        .where((DownloadRecord d) => _filter.matches(d.tag))
        .toList();
    return Column(
      children: <Widget>[
        TagFilterBar(
          tags: _tagsInUse,
          selected: _filter,
          hasUntagged: widget.recent.any((DownloadRecord d) => d.tag == null),
          onChanged: (TagFilter filter) => setState(() => _filter = filter),
        ),
        Expanded(child: widget.buildGrid(shown)),
      ],
    );
  }

  /// The tags this shelf actually holds, alphabetically.
  ///
  /// Off the rows on screen rather than from `knownDownloadTagsProvider`: they
  /// are the same set today, and reading the list being filtered is what keeps
  /// a chip from offering a tag that would show nothing.
  List<TagFolder> get _tagsInUse {
    final Set<TagFolder> tags = <TagFolder>{
      for (final DownloadRecord d in widget.recent) ?d.tag,
    };
    return tags.toList()..sort(
      (TagFolder a, TagFolder b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }
}
