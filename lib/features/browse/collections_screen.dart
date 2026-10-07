import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/band_fade_edge.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/features/browse/collection_listing_args.dart';

/// The collections one account publishes.
///
/// Two ways in, and only one of them needs anything configured: an uploader's
/// listing offers *their* public collections, which needs no key and no stored
/// username at all; Settings offers your own, which needs the username typed
/// once (no Wallhaven endpoint hands it back — see `SettingsRepository`).
class CollectionsScreen extends ConsumerWidget {
  /// Creates the screen listing [username]'s collections, or the stored user's
  /// own when [username] is null.
  const CollectionsScreen({this.username, this.seed, super.key});

  /// Whose collections to show. Null means "mine", read from settings.
  final String? username;

  /// The listing this was opened from, whose purity each collection inherits.
  final SearchQuery? seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? owner = username;
    return Scaffold(
      appBar: GradientAppBar.pushed(
        title: Text(owner == null ? l10n.collectionsMine : '@$owner'),
      ),
      body: BandFadeEdge(
        child: FutureBuilder<List<WallpaperCollection>>(
          // Rebuilt per build rather than held in a provider: this is a screen
          // that is pushed, read once and popped, and a family keyed on the
          // username would outlive it for nothing.
          future: owner == null
              ? ref.read(browseCollectionsProvider).mine()
              : ref.read(browseCollectionsProvider).of(owner),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<WallpaperCollection>> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final Object? error = snapshot.error;
                if (error != null) return _Failure(error: error);
                final List<WallpaperCollection> collections =
                    snapshot.data ?? const <WallpaperCollection>[];
                if (collections.isEmpty) {
                  return _Empty(message: l10n.collectionsNone);
                }
                return ListView.builder(
                  itemCount: collections.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _CollectionRow(
                        collection: collections[index],
                        seed: seed,
                      ),
                );
              },
        ),
      ),
    );
  }
}

/// One collection, and what committing to it would mean.
class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.collection, required this.seed});

  final WallpaperCollection collection;
  final SearchQuery? seed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.collections_bookmark_outlined),
      title: Text(collection.label),
      subtitle: Text(l10n.collectionCount(collection.count)),
      // The lock is the whole reason `isPublic` is carried into the domain: a
      // user looking at their own collections needs to see which of them
      // strangers can read.
      trailing: collection.isPublic
          ? null
          : Icon(
              Icons.lock_outline,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      onTap: () => context.pushNamed(
        TelaRoutes.collectionListingName,
        extra: CollectionListingArgs(collection: collection, seed: seed),
      ),
    );
  }
}

class _Failure extends ConsumerWidget {
  const _Failure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String sourceName = ref
        .watch(activeWallpaperSourceProvider)
        .displayName;
    return _Empty(
      message: error is SourceFailure
          ? localizedFailure(
              l10n,
              error as SourceFailure,
              sourceName: sourceName,
            )
          : l10n.errorUnexpected,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
