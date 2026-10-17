import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/download_queue_controller.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/pinned_download_tier.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/remembered_download_tag.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_choice.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/listing_origin.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/batch_routing.dart';
import 'package:tela/domain/models/download_location.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';

/// Puts the whole selection in the download queue and says so.
///
/// Returns false only when the user backed out — of the destination chooser or
/// of first-time folder setup — so the caller keeps a selection that was never
/// abandoned.
///
/// **Queued, not downloaded here.** The loop this replaced awaited one
/// multi-megabyte original after another inside a widget callback, so a hundred
/// wallpapers took as long as a hundred sequential downloads and closing the
/// app lost every one that had not landed — its only record of what was still
/// owed was a stack frame. The queue is durable, drains three at a time, and
/// can be paused, retried and cancelled per item.
///
/// The destination is resolved and any first-time folder granted *before*
/// anything is enqueued: the worker drains with no screen mounted and cannot
/// answer a chooser.
///
/// The tally that used to be reported here — "downloaded 9 of 12" — moves to
/// the queue tab, which can be honest per wallpaper instead of in aggregate.
///
/// ```dart
/// final bool queued = await queueBatchDownload(
///   context: context,
///   ref: ref,
///   wallpapers: selected,
///   messenger: messenger,
///   l10n: l10n,
/// );
/// ```
Future<bool> queueBatchDownload({
  required BuildContext context,
  required WidgetRef ref,
  required List<Wallpaper> wallpapers,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) async {
  // Captured before the first await, like the messenger the caller read: the
  // shelf can be gone by the time the *View* action is tapped, and a GoRouter
  // outlives the widget that was asked for it.
  final GoRouter router = GoRouter.of(context);
  // An explicit image anywhere in the selection routes all of it as explicit,
  // so one batch never splits across the gallery and the card.
  final BatchRouting routing = BatchRouting(<Purity>{
    for (final Wallpaper wallpaper in wallpapers) wallpaper.purity,
  });
  final ({bool proceed, StorageTier? tier, TagFolder? tag}) destination =
      await resolveDownloadDestination(
        context: context,
        ref: ref,
        purities: routing.purities,
        count: wallpapers.length,
        tagSample: wallpapers,
      );
  if (!destination.proceed || !context.mounted) return false;
  final bool ready = await ensureDownloadFolder(
    context: context,
    ref: ref,
    purities: routing.purities,
    tier: destination.tier,
  );
  if (!ready) return false;

  final int queued = await ref
      .read(downloadQueueControllerProvider.notifier)
      .enqueue(
        routing.apply(wallpapers),
        tier: destination.tier,
        tag: destination.tag,
      );
  _sayQueued(router, messenger, l10n, queued, wallpapers.length);
  return true;
}

/// Grants the files-outside-gallery folder now, while there is still a screen
/// to ask on.
///
/// The queue worker deliberately cannot run the chooser — see
/// `DrainDownloadQueue` — so a batch that would land in that tier has to settle
/// first-time setup up front, or every entry fails on the same unanswered
/// question. False when the user backed out of the chooser: nothing is queued
/// and the selection stays, exactly as backing out of the old inline setup did.
///
/// A folder that is granted but *unreachable* — an ejected card — is not
/// checked here and is not meant to be: that failure needs an attempt to
/// discover, and the queue now has somewhere honest to report it, per entry,
/// with a retry beside it.
///
/// Takes [purities] rather than the wallpapers themselves so a whole-listing
/// download can pass **what its query may return** instead of what its first
/// page happened to hold. A sample is the wrong evidence there: a listing whose
/// first page is all safe can still turn up a sketchy wallpaper forty pages in,
/// and the folder it needs would then never have been granted.
Future<bool> ensureDownloadFolder({
  required BuildContext context,
  required WidgetRef ref,
  required Set<Purity> purities,
  required StorageTier? tier,
}) async {
  final Set<Purity> outside = await _landingOutsideGallery(
    ref,
    purities,
    tier,
  );
  if (outside.isEmpty) return true;
  if (!context.mounted) return false;
  return ref
      .read(configuredDownloadProvider)
      .ensureFolder(
        ({required bool offerSdCard}) =>
            chooseDownloadVolume(context, offerSdCard: offerSdCard),
        purities: outside,
      );
}

/// The purities among [purities] headed for the tier that owns a folder —
/// each bucket of which needs its own, now that safe and explicit downloads
/// are placed apart.
///
/// A resolved [tier] answers it outright. A null one means "resolve per
/// wallpaper when it runs", so the same rule the download itself will apply is
/// applied here — [StorageSettings.tierWithPin], over the pin and each purity's
/// configured destination — rather than a second guess at it.
Future<Set<Purity>> _landingOutsideGallery(
  WidgetRef ref,
  Set<Purity> purities,
  StorageTier? tier,
) async {
  if (tier != null) {
    return tier == StorageTier.filesOutsideGallery ? purities : <Purity>{};
  }
  final SettingsRepository settings = ref.read(settingsRepositoryProvider);
  final StorageTier? pin = await ref.read(pinnedDownloadTierProvider.future);
  final StorageSettings storage = await settings.loadStorageSettings();
  return purities
      .where(
        (Purity purity) =>
            storage.tierWithPin(purity, pin) == StorageTier.filesOutsideGallery,
      )
      .toSet();
}

/// Says how many went into the queue, with a way to go and watch them.
///
/// Reports the *newly* queued count when it differs, because re-ticking a shelf
/// whose wallpapers are already waiting queues nothing new, and "queued 12"
/// over a queue that did not grow is the same kind of lie the old aggregate
/// tally was.
void _sayQueued(
  GoRouter router,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int queued,
  int total,
) {
  final String message = queued == total
      ? l10n.batchDownloadQueued(total)
      : l10n.batchDownloadQueuedPartial(queued, total);
  showTelaToast(
    messenger,
    message,
    action: SnackBarAction(
      label: l10n.batchDownloadQueuedView,
      onPressed: () => router.pushNamed(TelaRoutes.downloadHistoryName),
    ),
  );
}

/// Where a whole download lands: the one destination the user picks from the
/// intersection chooser. A dismissed chooser answers `proceed: false` so the
/// caller abandons and a selection stays as it was.
///
/// Shared by the ticked-selection batch and by a whole-listing download, which
/// is why it takes [purities] and [count] rather than deriving them: a listing
/// knows what it *may* return from its query long before it has fetched it.
/// [tagSample] is only ever evidence for the tag suggestion — a listing passes
/// its first page, which is representative enough for a name.
///
/// **A batch always asks. Nothing silences it — not even the pin.**
///
/// This has moved twice, and the reasoning is worth keeping. It first asked
/// only when the selection held a not-safe wallpaper, on the grounds that the
/// chooser existed for the destination a not-safe download must not enter
/// unasked; that left "put these thirty in my files folder" with no way to say
/// it at all. Then it asked unless a pin was set, since silencing the question
/// is exactly what "Keep sending here" means.
///
/// That second rule was wrong **here**, for a reason single downloads do not
/// share. A pin earns its keep by removing a question from a one-tap action you
/// perform constantly. A batch is neither: it is deliberate, it is rare, and it
/// commits many multi-megabyte files at once. Silencing it turned a pin the
/// user may have set weeks ago on a single wallpaper into an invisible standing
/// order over every future selection — which is precisely how it presented on
/// the device (owner, 2026-07-27: "when I batch download it's not asking where
/// I want it").
///
/// The pin is not ignored: it is handed to the chooser, which shows it,
/// starts its switch on, and offers **Stop**. One tap on the pinned destination
/// is the same download it would have made silently — the difference is that
/// the user can see what it is about to do, and change it.
Future<({bool proceed, StorageTier? tier, TagFolder? tag})>
resolveDownloadDestination({
  required BuildContext context,
  required WidgetRef ref,
  required Set<Purity> purities,
  required int count,
  required List<Wallpaper> tagSample,
  TagFolder? listingTag,
}) async {
  // Read before the first await, while the context is certainly still the one
  // under the shelf that published it. See `ListingOrigin`. [listingTag] is
  // for a caller that is *above* its shelf — the listing's own app bar, which
  // the grid's `ListingOrigin` never reaches.
  final TagFolder? searched = listingTag ?? ListingOrigin.folderOf(context);
  final StorageTier? pin = await ref.read(pinnedDownloadTierProvider.future);
  // The tag remembered for a *shared* destination, and the folders that already
  // exist there. A batch has no single tier until the user taps one, so the
  // private library's remembered tag and its folder names are deliberately not
  // reachable from here — this chooser opens over the ungated browse wall.
  // The tag the listing is already searching for beats the remembered one:
  // "I am looking at Leo (artist) and I want these filed under it" is a
  // statement about *this* selection, while a remembered tag is only an ambient
  // default. It is also free, so it is offered the instant the chooser opens
  // rather than after a lookup.
  final TagFolder? remembered = ref
      .read(rememberedDownloadTagProvider.notifier)
      .offeredFor(StorageTier.sharedGallery);
  final TagFolder? suggested = searched ?? remembered;
  final List<TagFolder> known = await ref.read(
    knownDownloadTagsProvider.future,
  );
  // Started but not awaited: the chooser opens on what is free and fills these
  // in when they land. On Wallhaven this is one request per wallpaper, and the
  // destination decision must not wait on a round trip per tile.
  final Future<List<TagCandidate>> suggestions = suggestedTagsFor(
    source: ref.read(activeWallpaperSourceProvider),
    listingTag: searched,
    known: known,
    selection: tagSample,
  );
  final DownloadLocation location = await ref
      .read(imageStoreProvider)
      .downloadLocation();
  if (!context.mounted) return (proceed: false, tier: null, tag: null);
  final DownloadDestinationChoice? choice =
      await chooseBatchDownloadDestination(
        context,
        purities: purities,
        count: count,
        pinnedTier: pin,
        suggestedTag: suggested,
        tagIsRemembered: searched == null && remembered != null,
        knownTags: known,
        tagSuggestions: suggestions,
        location: location,
      );
  if (choice == null) return (proceed: false, tier: null, tag: null);
  // Stop clears the pin and downloads nothing — the deliberate way out, and the
  // same contract the single chooser honours. Answering `proceed: false`
  // without clearing would leave the button doing nothing at all.
  if (choice.stopsPin) {
    await ref.read(pinnedDownloadTierProvider.notifier).clear();
    return (proceed: false, tier: null, tag: null);
  }
  if (choice.pin) {
    await ref.read(pinnedDownloadTierProvider.notifier).pin(choice.tier!);
  }
  // Remembered against the tier that was actually chosen, so a tag typed for
  // the private library stays out of the backed-up settings table — see
  // `RememberedDownloadTag`.
  if (choice.rememberTag) {
    await ref
        .read(rememberedDownloadTagProvider.notifier)
        .remember(choice.tag, tier: choice.tier!);
  }
  return (proceed: true, tier: choice.tier, tag: choice.tag);
}
