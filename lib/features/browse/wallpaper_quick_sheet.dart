import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/app/copy_wallpaper_action.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/pinned_download_tier.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/remembered_download_tag.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_choice.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/listing_origin.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/core/ui/sheet_header.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_target_sheet.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/use_cases/resolve_beam_files.dart';
import 'package:tela/domain/use_cases/suggest_tag_folders.dart';
import 'package:tela/features/beam/beam_sheet.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// What a long press on a wall tile offers, without opening the wallpaper.
///
/// Collecting used to cost a full round trip through the detail screen for
/// every wallpaper, which on a seven-tiles-per-row tablet wall is the slowest
/// part of it.
///
/// The *share menu* is still deliberately absent — it is a second sheet asking
/// which of three things to send, and a menu that opens a menu is the wrong
/// shortcut. [copy] is the one piece of it that comes over, because it is a
/// single act: one row, no follow-up question, and no purity condition of its
/// own since the clipboard is offered at every purity (`shareOptionsFor`).
enum WallpaperQuickAction {
  /// Add the wallpaper to favorites, or take it back out.
  favorite,

  /// Download to the destination configured for the wallpaper's purity.
  download,

  /// Apply it to a chosen Android surface.
  setWallpaper,

  /// Put the full-resolution image on the clipboard, to paste into another app.
  ///
  /// Offered at every purity, unlike the share sheet's image *file* — see
  /// `shareOptionsFor` for that decision and what it costs.
  copy,

  /// Send it to a machine on the local network.
  ///
  /// Offered whether or not it has been downloaded: an undownloaded wallpaper
  /// is fetched on the way out, so "send this to my computer" means the same
  /// thing here as it does on a download.
  beam,

  /// Give up on the shortcut and open the wallpaper properly.
  openDetail,

  /// Enter the shelf's multi-select mode with this wallpaper already ticked.
  ///
  /// Selection is reached through this sheet rather than by taking the long
  /// press over, because the two are the same gesture and D1 already spent it
  /// here. Deciding that twice is how they end up fighting.
  select,
}

/// Sends one wallpaper to a machine on the local network.
///
/// Resolves through `ResolveBeamFiles`, which fetches an undownloaded
/// wallpaper once into the preview cache and releases that copy however the
/// sheet ends. No purity gate here: `BeamWallpapers` enforces `mayBeamBitmap`
/// before a byte leaves, and refuses by name rather than by a missing button.
Future<void> _beam(
  BuildContext context,
  WidgetRef ref,
  Wallpaper wallpaper,
) async {
  final ResolvedBeamFiles resolved = await ref
      .read(resolveBeamFilesProvider)
      .call(<BeamCandidate>[BeamCandidate.ofWallpaper(wallpaper)]);
  try {
    if (!context.mounted) return;
    if (resolved.files.isEmpty) {
      _say(
        ScaffoldMessenger.of(context),
        AppLocalizations.of(context).beamNothingToSend(1),
        kind: ToastKind.failure,
      );
      return;
    }
    await BeamSheet.open(context, files: resolved.files);
  } finally {
    await resolved.release();
  }
}

/// Asks what to do with the long-pressed [wallpaper]; null when dismissed.
///
/// The caller runs the answer ([runWallpaperQuickAction]) rather than the sheet
/// running it itself, because every action outlives the sheet: the target
/// chooser and the result snackbar both need a context that is still mounted
/// once this one has popped.
///
/// Whether the *Select wallpapers* row appears is read from [context] here, at
/// the call site, and **not** inside the sheet: `showModalBottomSheet` builds
/// its child against the Navigator's context, which sits above every shelf, so
/// a `WallpaperSelectionScope` lookup from in there finds nothing. The tile's
/// own context is below the scope, which is why the question is answered before
/// the sheet opens rather than by it.
///
/// ```dart
/// final WallpaperQuickAction? action =
///     await chooseWallpaperQuickAction(context, wallpaper);
/// ```
Future<WallpaperQuickAction?> chooseWallpaperQuickAction(
  BuildContext context,
  Wallpaper wallpaper,
) {
  final bool canSelect = WallpaperSelectionScope.of(context) != null;
  return showModalBottomSheet<WallpaperQuickAction>(
    context: context,
    // Sized to its rows, not Material's default 9/16 cap: in tablet landscape
    // that cap cut *Open details* off at the bottom edge with nothing saying
    // the sheet scrolled (device survey, 2026-10-05). The scroll view below
    // still takes over where the rows outgrow the safe area.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) =>
        _QuickActionSheet(wallpaper: wallpaper, canSelect: canSelect),
  );
}

/// Performs [action] on [wallpaper], reporting the outcome over [context].
///
/// [openDetail] is the caller's own navigation rather than a push from here:
/// the wall opens its detail screen on a gallery *session* seeded at the
/// pressed index, and only the grid knows the listing that session walks.
///
/// Entering selection needs no callback for the mirror-image reason: the
/// selection is published above the tile by `SelectableWallpaperShelf`, so this
/// reaches it through [context] and every shelf gets the behaviour for free.
/// A shelf with no selection above it simply offers no such row.
Future<void> runWallpaperQuickAction({
  required BuildContext context,
  required WidgetRef ref,
  required Wallpaper wallpaper,
  required WallpaperQuickAction action,
  required VoidCallback openDetail,
}) async {
  switch (action) {
    case WallpaperQuickAction.favorite:
      await _toggleFavorite(ref, wallpaper);
    case WallpaperQuickAction.download:
      await _download(context, ref, wallpaper);
    case WallpaperQuickAction.setWallpaper:
      await _setWallpaper(context, ref, wallpaper);
    case WallpaperQuickAction.copy:
      await copyWallpaperToClipboard(
        context: context,
        ref: ref,
        wallpaper: wallpaper,
      );
    case WallpaperQuickAction.beam:
      await _beam(context, ref, wallpaper);
    case WallpaperQuickAction.openDetail:
      openDetail();
    case WallpaperQuickAction.select:
      WallpaperSelectionScope.of(context)?.selectOnly(wallpaper.ref.key);
  }
}

/// Deliberately silent: the tile's own corner mark appears or disappears under
/// the user's finger, which says it better than a snackbar over the wall would.
Future<void> _toggleFavorite(WidgetRef ref, Wallpaper wallpaper) async {
  await ref.read(toggleFavoriteProvider)(wallpaper);
  refreshFavorites(ref, wallpaper.ref);
}

Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  Wallpaper wallpaper,
) async {
  // A not-safe wallpaper opens the chooser first: the grid's only download path
  // is this row, so unlike the detail screen there is no long press to reach a
  // destination — and a sketchy download silently entering the gallery is the
  // exact surprise the tint on this row warns about. A safe one still routes
  // silently, as a plain tap does everywhere.
  final ({bool proceed, StorageTier? tier, TagFolder? tag}) destination =
      await _resolveDestination(context, ref, wallpaper);
  if (!destination.proceed || !context.mounted) return;

  // Read before the await, not after: the snackbar is shown across an async gap
  // and the wall may have been navigated away from by then.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  final DownloadOutcome outcome = await ref.read(configuredDownloadProvider)(
    wallpaper,
    chooseVolume: ({required bool offerSdCard}) =>
        chooseDownloadVolume(context, offerSdCard: offerSdCard),
    tier: destination.tier,
    tag: destination.tag,
  );
  switch (outcome) {
    case DownloadOutcome.saved:
      refreshDownloads(ref);
      _say(messenger, l10n.detailDownloadSuccess);
    case DownloadOutcome.folderUnavailable:
      _say(
        messenger,
        l10n.detailDownloadFolderUnavailable,
        kind: ToastKind.failure,
      );
    case DownloadOutcome.failed:
      _say(messenger, l10n.detailDownloadFailure, kind: ToastKind.failure);
    case DownloadOutcome.cancelled:
      break;
  }
}

/// Where a grid download should land: which tier, and whether to go ahead.
///
/// A safe wallpaper proceeds straight to its configured destination
/// (`tier: null`), the same silent routing a plain tap does. A not-safe one
/// opens the shared [chooseDownloadDestination] first — the grid's only remedy
/// for the destination it cannot otherwise pick — and a dismissed chooser
/// answers `proceed: false` so nothing downloads. A remembered choice is
/// persisted through the same controller Settings writes.
Future<({bool proceed, StorageTier? tier, TagFolder? tag})> _resolveDestination(
  BuildContext context,
  WidgetRef ref,
  Wallpaper wallpaper,
) async {
  // Read before the first await, while the context is certainly still the one
  // under the shelf that published it. See `ListingOrigin`.
  final TagFolder? searched = ListingOrigin.folderOf(context);
  final SettingsRepository settings = ref.read(settingsRepositoryProvider);
  // A pin is the whole point: with one set, downloading no longer asks. The
  // download use case applies the pin (invariant permitting), so a null tier
  // routes to it silently — even for a not-safe wallpaper the user pinned.
  final StorageTier? pin = await ref.read(pinnedDownloadTierProvider.future);
  // The tag the user is filing things under still applies to a download that
  // skips the chooser. "Keep using this tag" is a standing answer to a question
  // this path does not ask, and dropping it silently would file a quick
  // download outside the folder every other one is going to.
  final TagFolder? remembered = ref
      .read(rememberedDownloadTagProvider.notifier)
      .offeredFor(StorageTier.sharedGallery);
  if (pin != null || wallpaper.purity == Purity.sfw) {
    return (
      proceed: true,
      tier: null,
      // The listing's own tag first here too, so a quick download taken while
      // browsing one lands in it rather than in whatever was last used.
      tag: searched ?? remembered,
    );
  }
  final StorageSettings storage = await ref.read(
    storageSettingsProvider.future,
  );
  final DownloadDestinationStreak? streak = await settings
      .loadDestinationStreak(wallpaper.purity);
  final List<TagFolder> knownTags = await ref.read(
    knownDownloadTagsProvider.future,
  );
  final Future<List<TagCandidate>> suggestions = suggestedTagsFor(
    source: ref.read(activeWallpaperSourceProvider),
    listingTag: searched,
    known: knownTags,
    selection: <Wallpaper>[wallpaper],
  );
  if (!context.mounted) return (proceed: false, tier: null, tag: null);
  final DownloadDestinationChoice? choice = await chooseDownloadDestination(
    context,
    purity: wallpaper.purity,
    configuredTier: storage.tierFor(wallpaper.purity),
    streak: streak,
    suggestedTag: searched ?? remembered,
    tagIsRemembered: searched == null && remembered != null,
    knownTags: knownTags,
    tagSuggestions: suggestions,
  );
  if (choice == null || choice.stopsPin) {
    return (proceed: false, tier: null, tag: null);
  }
  if (choice.remember) {
    await ref
        .read(storageSettingsProvider.notifier)
        .route(wallpaper.purity, choice.tier!);
  }
  if (choice.pin) {
    await ref.read(pinnedDownloadTierProvider.notifier).pin(choice.tier!);
  }
  if (choice.rememberTag) {
    await ref
        .read(rememberedDownloadTagProvider.notifier)
        .remember(choice.tag, tier: choice.tier!);
  }
  return (proceed: true, tier: choice.tier, tag: choice.tag);
}

/// Asks Home/Lock/Both first, through the same chooser the detail screen and
/// the download history use, so the question reads identically everywhere.
Future<void> _setWallpaper(
  BuildContext context,
  WidgetRef ref,
  Wallpaper wallpaper,
) async {
  final WallpaperTarget? target = await chooseWallpaperTarget(context);
  if (target == null || !context.mounted) return;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  try {
    await ref.read(applyWallpaperProvider)(wallpaper, target);
    _say(messenger, l10n.detailApplySuccess);
  } on WallpaperApplyFailure {
    _say(messenger, l10n.detailApplyFailure, kind: ToastKind.failure);
  }
}

void _say(
  ScaffoldMessengerState messenger,
  String message, {
  ToastKind kind = ToastKind.success,
}) {
  showTelaToast(messenger, message, kind: kind);
}

class _QuickActionSheet extends ConsumerWidget {
  const _QuickActionSheet({required this.wallpaper, required this.canSelect});

  final Wallpaper wallpaper;

  /// Whether the shelf that opened this sheet can enter selection mode.
  final bool canSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // An unresolved read draws the empty heart rather than a spinner, for the
    // reason `FavoriteButton` gives: the answer is one local SQLite round trip
    // away, and a flicker of progress in a menu row reads worse than an outline
    // that fills in.
    final bool isFavorite =
        ref.watch(isFavoriteProvider(wallpaper.ref)).value ?? false;
    // Scrolls rather than clips. A modal sheet is capped at a fraction of the
    // screen, and five rows did not fit that cap on a short viewport — a phone
    // in landscape, or the 800x600 the widget tests run at, where this first
    // showed up as a 31px overflow. Six now, on a safe wallpaper. The column
    // still sizes to its content, so nothing scrolls where everything fits.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The wallpaper's id, the same label the detail screen uses. It
            // says *something* is selected, but on the device (2026-07-19) it
            // reads as a bare "Wallpaper k8lvqm" — which cannot tell you the
            // long press landed on the tile you aimed at, because nobody
            // recognises a wallhaven id by eye. A thumbnail here would; left
            // as a follow-up rather than widened into this slice.
            SheetHeader(title: l10n.detailPreviewLabel(wallpaper.id)),
            _tile(
              context,
              isFavorite ? Icons.favorite : Icons.favorite_border,
              isFavorite ? l10n.favoriteRemove : l10n.favoriteAdd,
              WallpaperQuickAction.favorite,
            ),
            _tile(
              context,
              Icons.download_outlined,
              l10n.detailDownload,
              WallpaperQuickAction.download,
              // The same warm signal the detail button wears, for the same
              // reason: a not-safe wallpaper here is one tap from the gallery,
              // and this row is where that tap begins.
              tint: purityAlertTint(
                Theme.of(context).colorScheme,
                wallpaper.purity,
              ),
            ),
            _tile(
              context,
              Icons.wallpaper_outlined,
              l10n.detailSetWallpaper,
              WallpaperQuickAction.setWallpaper,
            ),
            // Between the wallpaper's own actions and the two that navigate:
            // copying is something you do *to* the picture, not somewhere you
            // go.
            _tile(
              context,
              Icons.content_copy_outlined,
              l10n.detailShareClipboard,
              WallpaperQuickAction.copy,
            ),
            // Beside copy, for the same reason it sits beside share on the
            // detail bar: both are things you do *to* the picture rather than
            // somewhere you go.
            _tile(
              context,
              Icons.wifi_tethering,
              l10n.beamAction,
              WallpaperQuickAction.beam,
            ),
            _tile(
              context,
              Icons.info_outline,
              l10n.quickActionOpenDetail,
              WallpaperQuickAction.openDetail,
            ),
            if (canSelect)
              _tile(
                context,
                Icons.checklist,
                l10n.quickActionSelect,
                WallpaperQuickAction.select,
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label,
    WallpaperQuickAction action, {
    Color? tint,
  }) {
    return ListTile(
      leading: Icon(icon, color: tint),
      title: Text(label, style: tint == null ? null : TextStyle(color: tint)),
      onTap: () => Navigator.pop(context, action),
    );
  }
}
