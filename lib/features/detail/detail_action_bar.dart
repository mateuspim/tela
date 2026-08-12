import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/configured_download.dart';
import 'package:tela/app/delete_download_action.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/move_to_private_action.dart';
import 'package:tela/app/pinned_download_tier.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/remembered_download_tag.dart';
import 'package:tela/app/storage_settings_controller.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_choice.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/core/ui/purity_alert_tint.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_share_sheet.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/bitmap_export_rule.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/share_option.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_adjust_failure.dart';
import 'package:tela/domain/models/wallpaper_share_failure.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/use_cases/share_wallpaper.dart';
import 'package:tela/features/detail/crop_wallpaper_screen.dart';
import 'package:tela/features/favorites/favorite_button.dart';

/// Everything you can *do* to the shown wallpaper, as one row of icons.
///
/// Favorite, adjust, share, download — and, only for a wallpaper the download
/// history already holds, move-to-private and delete. It owns the five busy
/// flags its own buttons spin on, which is the reason it is a widget rather
/// than a list of builders: a download that is in flight concerns this row and
/// nothing else on the screen, so nothing else needs to rebuild for it.
///
/// Sits in the app bar when Detail is compact and above the metadata pane when
/// it is expanded; [expanded] is only about the arrangement — the favorite
/// pushed to the far left, away from the rest — never about what is offered.
///
/// ```dart
/// DetailActionBar(wallpaper: wallpaper, expanded: false)
/// ```
class DetailActionBar extends ConsumerStatefulWidget {
  /// Creates the action row for [wallpaper].
  const DetailActionBar({
    required this.wallpaper,
    this.expanded = false,
    super.key,
  });

  /// The wallpaper every action here acts on.
  final Wallpaper wallpaper;

  /// Whether to spread the favorite away from the rest, as the wide layout's
  /// information pane does.
  final bool expanded;

  @override
  ConsumerState<DetailActionBar> createState() => _DetailActionBarState();
}

class _DetailActionBarState extends ConsumerState<DetailActionBar> {
  bool _isDownloading = false;
  bool _isSharing = false;
  bool _isAdjusting = false;
  bool _isDeleting = false;
  bool _isMoving = false;

  Wallpaper get _wallpaper => widget.wallpaper;

  /// Frames the wallpaper before setting it — the long way round beside the
  /// apply button, which stays the shortest path (Wave 1's "≤3 taps").
  ///
  /// Two editors behind one button. An explicit wallpaper's pixels may not
  /// reach the OEM's editor (a separate app, [mayExportBitmap]), so it goes
  /// straight to tela's own in-app cropper. A safe one prefers the OEM editor —
  /// the same screen the gallery opens — and falls back to tela's cropper only
  /// where the device has none.
  Future<void> _adjust() async {
    if (!mayExportBitmap(_wallpaper.purity)) {
      _openCropEditor();
      return;
    }
    setState(() => _isAdjusting = true);
    final WallpaperAdjustFailure? failure = await _tryOpenSystemEditor();
    if (mounted) setState(() => _isAdjusting = false);
    if (failure == null || !mounted) return;
    if (failure.problem == WallpaperAdjustProblem.unavailable) {
      _openCropEditor();
    } else {
      _showResult(
        AppLocalizations.of(context).detailAdjustFailure,
        kind: ToastKind.failure,
      );
    }
  }

  /// Opens the OEM editor; returns null on success, or the failure to route on.
  ///
  /// Deliberately silent on success: tela launches the editor and never hears
  /// what the user did there, so it has no outcome it could honestly report.
  Future<WallpaperAdjustFailure?> _tryOpenSystemEditor() async {
    try {
      await ref.read(adjustWallpaperProvider)(_wallpaper);
      return null;
    } on WallpaperAdjustFailure catch (failure) {
      return failure;
    }
  }

  /// Pushes tela's own cropper. It applies and pops itself, so nothing is
  /// awaited here — the detail screen simply returns to view when it closes.
  void _openCropEditor() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              CropWallpaperScreen(wallpaper: _wallpaper),
        ),
      ),
    );
  }

  /// Offers only the tiers this wallpaper's purity is allowed to land in, so a
  /// one-off override cannot do what the settings screen forbids — the dialog
  /// asks the domain for that list rather than being told it from here.
  ///
  /// Feeds the chooser what it needs to notice a habit: where a plain tap
  /// already routes, and the run of recent same-destination downloads. When the
  /// user takes the "Always" offer, the new default is persisted through the
  /// same controller the settings screen writes, so that screen stays in step.
  Future<void> _chooseDownloadTier() async {
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    final StorageSettings storage = await ref.read(
      storageSettingsProvider.future,
    );
    final DownloadDestinationStreak? streak = await settings
        .loadDestinationStreak(_wallpaper.purity);
    final StorageTier? pin = await ref.read(
      pinnedDownloadTierProvider.future,
    );
    // Against the shared tiers, which is what this chooser may offer: the
    // private library's folder names do not belong on a screen with no lock in
    // front of it. See `DownloadTagField`.
    final TagFolder? suggestedTag = ref
        .read(rememberedDownloadTagProvider.notifier)
        .offeredFor(StorageTier.sharedGallery);
    final List<TagFolder> knownTags = await ref.read(
      knownDownloadTagsProvider.future,
    );
    if (!mounted) return;
    final DownloadDestinationChoice? choice = await chooseDownloadDestination(
      context,
      purity: _wallpaper.purity,
      configuredTier: storage.tierFor(_wallpaper.purity),
      streak: streak,
      pinnedTier: pin,
      suggestedTag: suggestedTag,
      knownTags: knownTags,
    );
    if (choice == null) return;
    // Stop clears the pin and downloads nothing — the deliberate way out.
    if (choice.stopsPin) {
      await ref.read(pinnedDownloadTierProvider.notifier).clear();
      return;
    }
    if (choice.remember) {
      await ref
          .read(storageSettingsProvider.notifier)
          .route(_wallpaper.purity, choice.tier!);
    }
    if (choice.pin) {
      await ref.read(pinnedDownloadTierProvider.notifier).pin(choice.tier!);
    }
    // Remembered against the tier actually chosen, so a tag picked for the
    // private library never reaches the backed-up settings table.
    if (choice.rememberTag) {
      await ref
          .read(rememberedDownloadTagProvider.notifier)
          .remember(choice.tag, tier: choice.tier!);
    }
    if (!mounted) return;
    await _download(choice.tier, choice.tag);
  }

  /// Downloads to [tier], or to the configured destination when it is null.
  ///
  /// [refreshDownloads] is what makes the new file visible to the screens that
  /// exist to show it; see its docstring for why skipping it looked like the
  /// download never saved.
  Future<void> _download([StorageTier? tier, TagFolder? tag]) async {
    setState(() => _isDownloading = true);
    try {
      final DownloadOutcome outcome =
          await ref.read(configuredDownloadProvider)(
            _wallpaper,
            tier: tier,
            tag: tag,
            chooseVolume: ({required bool offerSdCard}) =>
                chooseDownloadVolume(context, offerSdCard: offerSdCard),
          );
      _reportDownload(outcome);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// A dismissed folder chooser is silent: the user stopped, did not fail.
  void _reportDownload(DownloadOutcome outcome) {
    if (!mounted) return;
    switch (outcome) {
      case DownloadOutcome.saved:
        refreshDownloads(ref);
        _showResult(AppLocalizations.of(context).detailDownloadSuccess);
      case DownloadOutcome.folderUnavailable:
        _showResult(
          AppLocalizations.of(context).detailDownloadFolderUnavailable,
          kind: ToastKind.failure,
        );
      case DownloadOutcome.failed:
        _showResult(
          AppLocalizations.of(context).detailDownloadFailure,
          kind: ToastKind.failure,
        );
      case DownloadOutcome.cancelled:
        break;
    }
  }

  /// The history row for the shown wallpaper, or null when it is not a download
  /// tela can reach from here.
  ///
  /// The "free" lookup J leans on: the history already carries the tier and the
  /// location a hard delete needs, so the detail screen offers *Delete from
  /// device* only for a wallpaper that is in it. Explicit and app-private
  /// downloads are deliberately absent — they live behind the private library's
  /// lock, and offering their delete on this ungated screen would leak that
  /// they exist.
  DownloadRecord? _downloadedRecord() {
    final List<DownloadRecord> recent =
        ref.watch(recentDownloadsProvider).value ?? const <DownloadRecord>[];
    for (final DownloadRecord record in recent) {
      if (record.wallpaper.id == _wallpaper.id) return record;
    }
    return null;
  }

  /// Moves the downloaded file into the private library.
  ///
  /// Both buttons retire themselves afterwards, and correctly: the history row
  /// is forgotten by the move, so `_downloadedRecord()` answers null and this
  /// screen goes back to offering a plain download. The wallpaper stays
  /// browsable — only tela's record of having it here does not.
  Future<void> _moveToPrivateLibrary(DownloadRecord record) async {
    setState(() => _isMoving = true);
    await confirmAndMoveToPrivate(
      context: context,
      ref: ref,
      records: <DownloadRecord>[record],
    );
    if (!mounted) return;
    setState(() => _isMoving = false);
  }

  /// Hard-deletes the downloaded file, then refreshes so the button that opened
  /// this retires itself — the wallpaper stays browsable, only its download is
  /// gone.
  Future<void> _deleteFromDevice(DownloadRecord record) async {
    setState(() => _isDeleting = true);
    final bool deleted = await confirmAndDeleteDownload(
      context: context,
      ref: ref,
      wallpaper: record.wallpaper.ref,
      tier: record.tier,
      location: record.location,
    );
    if (!mounted) return;
    setState(() => _isDeleting = false);
    if (deleted) refreshDownloads(ref);
  }

  /// Offers only the share options this wallpaper's purity allows, so an
  /// explicit wallpaper is never given the chance to send its image file — the
  /// menu and the use case enforce the same rule (see [shareOptionsFor]).
  Future<void> _chooseShare() async {
    final String sourceName = ref
        .read(wallpaperSourceForProvider(_wallpaper.source))
        .displayName;
    final ShareOption? option = await chooseShareOption(
      context,
      shareOptionsFor(_wallpaper.purity),
      sourceName: sourceName,
    );
    if (option == null || !mounted) return;
    await _share(option);
  }

  Future<void> _share(ShareOption option) async {
    setState(() => _isSharing = true);
    try {
      final ShareWallpaper share = ref.read(shareWallpaperProvider);
      await switch (option) {
        ShareOption.link => share.link(_wallpaper),
        ShareOption.image => share.image(_wallpaper),
      };
    } on WallpaperShareFailure {
      if (mounted) {
        _showResult(
          AppLocalizations.of(context).detailShareFailure,
          kind: ToastKind.failure,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showResult(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DownloadRecord? downloaded = _downloadedRecord();
    return Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        FavoriteButton(wallpaper: _wallpaper),
        if (widget.expanded) const Spacer(),
        _adjustButton(l10n),
        _shareButton(l10n),
        _downloadButton(l10n),
        if (downloaded != null) _moveToPrivateButton(l10n, downloaded),
        if (downloaded != null) _deleteButton(l10n, downloaded),
      ],
    );
  }

  /// Shown for every purity now that tela has its own in-app cropper: [_adjust]
  /// routes explicit wallpapers there rather than to the OEM editor, so the
  /// button no longer needs to be withheld to honour [mayExportBitmap].
  Widget _adjustButton(AppLocalizations l10n) {
    return IconButton(
      key: const Key('detail-adjust'),
      onPressed: _isAdjusting ? null : _adjust,
      tooltip: l10n.detailAdjust,
      icon: _isAdjusting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.crop_outlined),
    );
  }

  Widget _shareButton(AppLocalizations l10n) {
    return IconButton(
      onPressed: _isSharing ? null : _chooseShare,
      tooltip: l10n.detailShare,
      icon: _isSharing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.share_outlined),
    );
  }

  /// Downloads on a tap, offers the destination on a long press — and says
  /// which of the two this wallpaper wants before either happens.
  ///
  /// The tint is the whole point (see `purityAlertTint`): a long press is an
  /// invisible affordance, so a wallpaper that deserves a deliberate
  /// destination has to *ask* for one. Sketchy is the case that stings —
  /// nothing else on this screen distinguishes it from safe, and it routes to
  /// the gallery by default.
  Widget _downloadButton(AppLocalizations l10n) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color? tint = purityAlertTint(colors, _wallpaper.purity);
    return Semantics(
      button: true,
      label: l10n.detailDownload,
      // The purity rides in the hint, not the label: the label is what the
      // control *is*, and every caller that looks this button up by name —
      // including the tests — must keep finding one called "Download".
      hint: tint == null
          ? null
          : l10n.detailDownloadPurity(purityLabel(l10n, _wallpaper.purity)),
      child: InkWell(
        onTap: _isDownloading ? null : _download,
        onLongPress: _isDownloading ? null : _chooseDownloadTier,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _isDownloading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.download_outlined, color: tint),
        ),
      ),
    );
  }

  /// Shown only for a wallpaper already in the download history: the file and
  /// its row, deleted together. Its own confirmation lives in
  /// [confirmAndDeleteDownload], suppressed where Android's own takes over.
  /// Moves the downloaded file into the private library.
  ///
  /// Behind the **same gate as [_deleteButton]** — `_downloadedRecord()` — and
  /// that is deliberate rather than convenient. That lookup reads the download
  /// history, which never holds an explicit or app-private download, so an
  /// action offered from it can never disclose that one exists on this ungated
  /// screen. A second gate written for this button is a second chance to get
  /// that wrong.
  Widget _moveToPrivateButton(AppLocalizations l10n, DownloadRecord record) {
    return IconButton(
      key: const Key('detail-move-to-private'),
      onPressed: _isMoving ? null : () => _moveToPrivateLibrary(record),
      tooltip: l10n.moveToPrivateAction,
      icon: _isMoving
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lock_outline),
    );
  }

  Widget _deleteButton(AppLocalizations l10n, DownloadRecord record) {
    return IconButton(
      key: const Key('detail-delete'),
      onPressed: _isDeleting ? null : () => _deleteFromDevice(record),
      tooltip: l10n.downloadDeleteMenu,
      icon: _isDeleting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline),
    );
  }
}
