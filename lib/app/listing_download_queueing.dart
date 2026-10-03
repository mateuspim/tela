import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/batch_download_queueing.dart';
import 'package:tela/app/listing_download_walk.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/listing_download_dialog.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/listing_download_size.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper_page.dart';

/// Queues every wallpaper a listing holds, without the user scrolling to it.
///
/// The owner's ask (2026-08-25): *"if i still didnt select all images from a
/// user or tag, i can select all from user/tag to download so i dont need to
/// scroll all the way down to select all"*. **Selection could not carry this**
/// — a ticked id is resolved back against the wallpapers the shelf has loaded
/// (`SelectableWallpaperShelf`), by a rule that exists so a stale tick cannot
/// act on a wallpaper that has since gone. Ticking ids for pages nobody has
/// fetched would have them silently dropped at download time. So this does not
/// tick anything: it walks the listing and feeds the queue directly.
///
/// The order is load-bearing. Page 1 is fetched **once** and does three jobs —
/// it sizes the listing for the confirmation, it is the sample the tag
/// suggestion reads, and it is the first page queued. The destination is then
/// settled while a screen is still up, because the queue worker drains with
/// nothing mounted and cannot answer a chooser.
///
/// ```dart
/// await queueListingDownload(
///   context: context,
///   ref: ref,
///   query: query,
///   listing: '#anime',
///   folder: link.folderName,
///   messenger: ScaffoldMessenger.of(context),
///   l10n: l10n,
/// );
/// ```
Future<void> queueListingDownload({
  required BuildContext context,
  required WidgetRef ref,
  required SearchQuery query,
  required String listing,
  required TagFolder? folder,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) async {
  // Captured before the first await: a pushed listing can be gone by the time
  // the *View* action is tapped, and a GoRouter outlives the widget.
  final GoRouter router = GoRouter.of(context);
  if (ref.read(listingDownloadWalkProvider.notifier).isRunning) {
    showTelaToast(messenger, l10n.listingDownloadAllAlreadyRunning);
    return;
  }
  final WallpaperPage? first = await _firstPage(ref, query, messenger, l10n);
  if (first == null || !context.mounted) return;
  final ListingDownloadSize size = ListingDownloadSize.of(first);
  if (!await confirmListingDownload(context, listing: listing, size: size)) {
    return;
  }
  if (!context.mounted) return;
  final ({bool proceed, StorageTier? tier, TagFolder? tag})? destination =
      await _destination(context, ref, query, first, folder);
  if (destination == null || !destination.proceed) return;

  _sayWalking(messenger, l10n, listing, ref);
  final int queued = await ref
      .read(listingDownloadWalkProvider.notifier)
      .start(
        query: query,
        first: first,
        listing: listing,
        tier: destination.tier,
        tag: destination.tag,
      );
  _sayQueued(router, messenger, l10n, queued);
}

/// The listing's first page, or null with the failure already reported.
///
/// A listing that cannot be fetched has no size, so there is nothing honest to
/// confirm — the user is told and nothing is queued.
Future<WallpaperPage?> _firstPage(
  WidgetRef ref,
  SearchQuery query,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  try {
    return await ref.read(searchWallpapersProvider)(query.atPage(1));
  } on Object {
    showTelaToast(messenger, l10n.errorUnexpected);
    return null;
  }
}

/// Settles where the whole listing lands, while a screen is still up.
///
/// The purities come from the **query**, not from the first page: a listing
/// whose opening page is all safe can still turn up a sketchy wallpaper forty
/// pages in, and a folder grant decided on the sample would never have been
/// asked for. See [ensureDownloadFolder].
Future<({bool proceed, StorageTier? tier, TagFolder? tag})?> _destination(
  BuildContext context,
  WidgetRef ref,
  SearchQuery query,
  WallpaperPage first,
  TagFolder? folder,
) async {
  final Set<Purity> purities = query.purity.purities;
  final ({bool proceed, StorageTier? tier, TagFolder? tag}) chosen =
      await resolveDownloadDestination(
        context: context,
        ref: ref,
        purities: purities,
        count: first.total ?? first.wallpapers.length,
        tagSample: first.wallpapers,
        // Handed over, not inherited: *Download all* sits in the app bar,
        // above the grid's `ListingOrigin`, so the chooser would otherwise
        // never hear the tag and look one up per wallpaper instead — "it
        // still needs to check some images ... i just want to use like
        // minimalist" (the owner, 2026-09-30).
        listingTag: folder,
      );
  if (!chosen.proceed || !context.mounted) return null;
  final bool ready = await ensureDownloadFolder(
    context: context,
    ref: ref,
    purities: purities,
    tier: chosen.tier,
  );
  if (!ready) return null;
  // The listing's own name beats whatever the chooser suggested only when the
  // chooser had nothing: `ListingOrigin` already offers it as the suggestion,
  // so a user who typed something else meant it.
  return (proceed: true, tier: chosen.tier, tag: chosen.tag ?? folder);
}

/// Says the walk has started, with the way to stop it.
///
/// A walk of a large listing runs for minutes behind whatever the user does
/// next, so the only honest moment to offer *Stop* is while it is running.
void _sayWalking(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String listing,
  WidgetRef ref,
) {
  showTelaToast(
    messenger,
    l10n.listingDownloadAllStarted(listing),
    action: SnackBarAction(
      label: l10n.listingDownloadAllStop,
      onPressed: ref.read(listingDownloadWalkProvider.notifier).stop,
    ),
  );
}

/// Says how many the queue accepted, with a way to go and watch them.
///
/// The count is what the queue *newly* took, not what was walked past: the
/// queue is idempotent per wallpaper, so re-running a listing already waiting
/// adds nothing and must not claim to have.
void _sayQueued(
  GoRouter router,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int queued,
) {
  showTelaToast(
    messenger,
    l10n.batchDownloadQueued(queued),
    action: SnackBarAction(
      label: l10n.batchDownloadQueuedView,
      onPressed: () => router.pushNamed(TelaRoutes.downloadHistoryName),
    ),
  );
}
