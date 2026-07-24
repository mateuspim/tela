import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// Switches which site browse is reading from.
///
/// **Draws nothing while tela has one source registered**, which is the state
/// it ships in: a switcher offering a single choice is a control that cannot do
/// anything, and it would cost the app bar a slot the filter button wants. It
/// appears the moment a second adapter is added to the registry — no feature
/// change, which is the whole point of `wallpaperSourcesProvider`.
///
/// Switching resets the query (see `BrowseQueryController`): filters are not
/// portable between sources.
class BrowseSourceButton extends ConsumerWidget {
  /// Creates the switcher.
  const BrowseSourceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WallpaperSource> sources = ref.watch(wallpaperSourcesProvider);
    if (sources.length < 2) return const SizedBox.shrink();

    final WallpaperSource active = ref.watch(activeWallpaperSourceProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PopupMenuButton<SourceId>(
      tooltip: l10n.browseSource(active.displayName),
      initialValue: active.id,
      onSelected: (SourceId id) =>
          ref.read(activeSourceProvider.notifier).choose(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(active.displayName),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<SourceId>>[
        for (final WallpaperSource source in sources)
          CheckedPopupMenuItem<SourceId>(
            value: source.id,
            checked: source.id == active.id,
            child: Text(source.displayName),
          ),
      ],
    );
  }
}
