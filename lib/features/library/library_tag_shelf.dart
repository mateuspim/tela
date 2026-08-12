import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/shelf_header.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// The Library tab's list of tag folders, each opening the history filtered.
///
/// **Absent entirely when nothing is tagged**, which is most of a library's
/// life: a section headed "Tags" over an empty row is a promise of a feature
/// rather than a use of one, and this screen already had to fight for its
/// vertical space (D2 — two destination rows over a favorites grid left a
/// screen and a half of black on a 2560x1600 panel).
///
/// Counts come from the download history only. The private library's tags are
/// deliberately not here: this screen has no lock in front of it, and its
/// folder names disclose as much as its file paths.
class LibraryTagShelf extends ConsumerWidget {
  /// Creates the tag section.
  const LibraryTagShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DownloadRecord>? recent = ref
        .watch(recentDownloadsProvider)
        .value;
    if (recent == null) return const SizedBox.shrink();
    final Map<TagFolder, int> counts = _countByTag(recent);
    if (counts.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ShelfHeader(label: l10n.libraryTags, count: counts.length),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: <Widget>[
              for (final MapEntry<TagFolder, int> e in counts.entries)
                _tagChip(context, l10n, e.key, e.value),
            ],
          ),
        ),
      ],
    );
  }

  /// One tag, its count, and the tap that opens the history narrowed to it.
  Widget _tagChip(
    BuildContext context,
    AppLocalizations l10n,
    TagFolder tag,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ActionChip(
          avatar: const Icon(Icons.folder_outlined, size: 18),
          label: Text('${tag.name}  ${l10n.libraryTagCount(count)}'),
          onPressed: () => context.pushNamed(
            TelaRoutes.downloadHistoryName,
            queryParameters: <String, String>{'tag': tag.name},
          ),
        ),
      ),
    );
  }

  /// How many downloads sit under each tag, alphabetically.
  ///
  /// Untagged downloads are not counted: they are not a folder, and a row for
  /// them here would open a filter the history offers of its own accord.
  Map<TagFolder, int> _countByTag(List<DownloadRecord> recent) {
    final Map<TagFolder, int> counts = <TagFolder, int>{};
    for (final DownloadRecord download in recent) {
      final TagFolder? tag = download.tag;
      if (tag == null) continue;
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
    final List<TagFolder> ordered = counts.keys.toList()
      ..sort(
        (TagFolder a, TagFolder b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return <TagFolder, int>{
      for (final TagFolder tag in ordered) tag: counts[tag]!,
    };
  }
}
