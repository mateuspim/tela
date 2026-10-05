import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/app/move_to_private_action.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/retag_downloads_action.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/gradient_app_bar.dart';
import 'package:tela/core/ui/justified_wallpaper_grid.dart';
import 'package:tela/core/ui/selection_shelf.dart';
import 'package:tela/core/ui/shelf_hero_tag.dart';
import 'package:tela/core/ui/tag_filter_bar.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_grid_columns.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';
import 'package:tela/core/ui/wallpaper_source_badge.dart';
import 'package:tela/core/ui/wallpaper_source_labels_scope.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/private_image.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/vault_thumbnail.dart';
import 'package:tela/domain/use_cases/resolve_beam_files.dart';
import 'package:tela/features/beam/beam_sheet.dart';
import 'package:tela/features/private_library/private_secure_access.dart';
import 'package:tela/features/settings/beam_explicit_switch.dart';

/// The app-private tier, which nothing but tela can open.
///
/// Holds `FLAG_SECURE` while on screen and satisfies the app-lock before it
/// lists anything — both through [PrivateSecureAccess], which the
/// fullscreen viewer shares so the protection survives the whole private flow.
/// Tapping a tile opens that image in the secure viewer. A long press enters
/// multi-select — the same rule the other library shelves follow — and deleting
/// one file is the batch delete at a count of one, so the permanence warning is
/// worded once and shown for both.
class PrivateLibraryScreen extends ConsumerStatefulWidget {
  /// Creates the private library.
  const PrivateLibraryScreen({super.key});

  @override
  ConsumerState<PrivateLibraryScreen> createState() =>
      _PrivateLibraryScreenState();
}

class _PrivateLibraryScreenState extends ConsumerState<PrivateLibraryScreen>
    with PrivateSecureAccess<PrivateLibraryScreen> {
  @override
  void initState() {
    super.initState();
    beginPrivateAccess();
  }

  @override
  void dispose() {
    endPrivateAccess();
    super.dispose();
  }

  /// Which tag the grid is narrowed to. Local state: it is a view of what is
  /// on screen, not something another screen has any business reading.
  TagFilter _tagFilter = const TagFilter.all();

  /// Real pixel bounds for a vault tile, resolved lazily as it comes on
  /// screen and kept here so the row that needed them survives a scroll.
  ///
  /// The vault's own listing carries none of this any more — see
  /// `SafVaultListing.describe` — so every vault tile starts with an unknown
  /// aspect ratio and asks for its own, once, the first time it is actually
  /// built. Keyed by `WallpaperRef.key`, matching every other per-image map
  /// this screen already uses.
  final Map<String, VaultThumbnail> _vaultThumbnails =
      <String, VaultThumbnail>{};

  void _onVaultThumbnailResolved(String key, VaultThumbnail thumbnail) {
    if (!mounted || _vaultThumbnails[key] == thumbnail) return;
    setState(() => _vaultThumbnails[key] = thumbnail);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SelectionShelfScope(
      child: Scaffold(
        appBar: GradientAppBar.pushed(
          toolbarHeight: 72,
          title: Text(
            l10n.privateLibraryTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          // Collapses while selecting, when Select hides itself — see
          // CapsuleActionCluster.
          actions: const <Widget>[
            CapsuleActionCluster(children: <Widget>[SelectModeButton()]),
            SizedBox(width: 16),
          ],
        ),
        body: _body(context, l10n),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isCheckingLock) return const Center(child: CircularProgressIndicator());
    if (!isUnlocked) return _locked(l10n);
    return ref
        .watch(privateImagesProvider)
        .when(
          data: (List<PrivateImage> stored) => _filtered(context, l10n, stored),
          loading: () => const WallpaperGridSkeleton(),
          error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
            icon: Icons.error_outline,
            message: l10n.privateLibraryUnavailable,
          ),
        );
  }

  /// The grid with its tag filter above it.
  ///
  /// Only reachable past [isUnlocked], which is the whole point: these chips
  /// are the private library's folder names, and they are as disclosing as its
  /// file paths. Nothing outside this screen is ever handed them — the download
  /// chooser deliberately offers the shared tiers' tags only.
  Widget _filtered(
    BuildContext context,
    AppLocalizations l10n,
    List<PrivateImage> stored,
  ) {
    final List<PrivateImage> shown = stored
        .where((PrivateImage i) => _tagFilter.matches(i.tag))
        .toList();
    return Column(
      children: <Widget>[
        TagFilterBar(
          tags: _tagsIn(stored),
          selected: _tagFilter,
          hasUntagged: stored.any((PrivateImage i) => i.tag == null),
          onChanged: (TagFilter filter) => setState(() => _tagFilter = filter),
        ),
        Expanded(child: _grid(context, l10n, shown)),
      ],
    );
  }

  /// The tags this library holds, alphabetically — read off the files, since
  /// this tier keeps no rows to read them from.
  List<TagFolder> _tagsIn(List<PrivateImage> stored) {
    final Set<TagFolder> tags = <TagFolder>{
      for (final PrivateImage image in stored) ?image.tag,
    };
    return tags.toList()..sort(
      (TagFolder a, TagFolder b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  /// What a failed or dismissed prompt leaves behind: a way to try again, and
  /// nothing else. No count, no thumbnails, no hint of what is in there.
  Widget _locked(AppLocalizations l10n) {
    return WallpaperStatusView(
      icon: Icons.lock_outline,
      message: l10n.privateLibraryLocked,
      actionLabel: l10n.privateLibraryUnlock,
      onAction: authenticate,
    );
  }

  Widget _grid(
    BuildContext context,
    AppLocalizations l10n,
    List<PrivateImage> stored,
  ) {
    if (stored.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.lock_open_outlined,
        message: l10n.privateLibraryEmpty,
      );
    }
    // Rows keyed to each file's real aspect ratio: the app-private tier's is
    // known from the listing, a vault tile's arrives later from its own
    // lazily-resolved thumbnail, and either one falls back square — the same
    // safe reading a corrupt file already gets — until it is known.
    return SelectionShelf(
      itemIds: <String>[for (final PrivateImage image in stored) image.ref.key],
      // Deleting is the only batch that means anything here. These files are
      // already on the device, so there is nothing to download, and favoriting
      // is a Wallhaven-wallpaper idea the private tier deliberately has no part
      // in — a favorite would be a second, unlocked index of what is in here.
      actions: <SelectionAction>[
        // Refiling never leaves the tier, so unlike the two below it discloses
        // nothing and takes nothing away — it is the safe one, and it goes
        // first.
        SelectionAction(
          icon: Icons.folder_outlined,
          label: l10n.retagAction,
          run: _retagSelected,
        ),
        // Withheld entirely while the gate is off, rather than shown and
        // refused: the domain refuses too (`BeamWallpapers`), but an action
        // that is never offered cannot be reached by muscle memory, which is
        // the whole point of the gate being opt-in.
        if (ref.watch(explicitBeamProvider).value ?? false)
          SelectionAction(
            icon: Icons.wifi_tethering,
            label: l10n.beamAction,
            run: _beamSelected,
          ),
        SelectionAction(
          icon: Icons.lock_open_outlined,
          label: l10n.moveOutOfPrivateAction,
          run: _moveSelectedOut,
        ),
        SelectionAction(
          icon: Icons.delete_outline,
          label: l10n.privateLibraryDelete,
          run: _deleteSelected,
        ),
      ],
      child: JustifiedWallpaperGrid(
        itemCount: stored.length,
        aspectRatioOf: (int index) => _aspectRatioOf(stored[index]),
        itemBuilder: (BuildContext context, int index, double _, double _) =>
            _tile(context, stored, index),
      ),
    );
  }

  double _aspectRatioOf(PrivateImage image) {
    final double? known = image.aspectRatio;
    if (known != null) return known;
    return _vaultThumbnails[image.ref.key]?.aspectRatio ?? 1;
  }

  Widget _tile(BuildContext context, List<PrivateImage> stored, int index) {
    final gestures = selectableTileGestures(
      context: context,
      wallpaperKey: stored[index].ref.key,
      onOpen: () => _open(context, stored, index),
      longPressSelects: true,
    );
    return _PrivateTile(
      image: stored[index],
      position: index,
      onTap: gestures.onTap,
      onLongPress: gestures.onLongPress,
      cachedThumbnail: _vaultThumbnails[stored[index].ref.key],
      onThumbnailResolved: _onVaultThumbnailResolved,
    );
  }

  /// Opens the whole private tier in the secure viewer, on the tapped image.
  ///
  /// The session is the complete local list, so it never pages — like Favorites
  /// and History. Its creator disposes it when the viewer returns.
  void _open(BuildContext context, List<PrivateImage> stored, int index) {
    unawaited(_pushViewer(context, stored, index));
  }

  Future<void> _pushViewer(
    BuildContext context,
    List<PrivateImage> stored,
    int index,
  ) async {
    final GallerySessionController<PrivateImage> session =
        GallerySessionController<PrivateImage>(
          identity: 'private-library',
          items: stored,
          initialIndex: index,
          itemKey: (PrivateImage image) => image.ref.key,
        );
    try {
      await context.pushNamed<void>(
        TelaRoutes.privateViewerName,
        extra: session,
      );
    } finally {
      session.dispose();
    }
  }

  /// Confirms, then deletes every ticked file, reporting what actually went.
  ///
  /// Answers false on a declined confirmation so the ticks survive it — the
  /// user cancelled the deletion, not the selection.
  Future<bool> _deleteSelected(List<String> keys) async {
    if (keys.isEmpty) return false;
    if (!await _confirmDelete(keys.length)) return false;
    if (!mounted) return false;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int deleted = await _deleteAll(keys);
    ref.invalidate(privateImagesProvider);
    if (mounted) _show(_deleteOutcome(l10n, deleted, keys.length));
    return true;
  }

  /// Moves the ticked images out to the files folder.
  ///
  /// The one batch besides deleting that means anything here, and the only way
  /// back out of this tier: a private image can never be re-downloaded from the
  /// grid, because the grid holds no wallpaper to re-download — just a ref and
  /// Refiles the ticked images under a tag the user names.
  ///
  /// Stays inside the private tier, so there is nothing to confirm and nothing
  /// disclosed — the naming dialog is the whole interaction.
  Future<bool> _retagSelected(List<String> keys) async {
    if (keys.isEmpty) return false;
    final List<PrivateImage> selected = _imagesFor(keys);
    if (selected.isEmpty || !mounted) return false;
    return retagPrivateImages(context: context, ref: ref, images: selected);
  }

  /// a file. `confirmAndMoveOutOfPrivate` owns the confirmation, which has to
  /// say two surprising things (never to Photos, and tela stops tracking it),
  /// and the folder grant that tier needs.
  ///
  /// Answers false on a declined confirmation so the ticks survive it, the same
  /// rule [_deleteSelected] follows.
  Future<bool> _moveSelectedOut(List<String> keys) async {
    if (keys.isEmpty) return false;
    final List<PrivateImage> selected = _imagesFor(keys);
    if (selected.isEmpty || !mounted) return false;
    final bool moved = await confirmAndMoveOutOfPrivate(
      context: context,
      ref: ref,
      images: selected,
    );
    if (moved) ref.invalidate(privateImagesProvider);
    return moved;
  }

  /// Sends the ticked images to a machine on the local network.
  ///
  /// Resolves through [ResolveBeamFiles] first, because a vault image's
  /// location is a `content:` SAF URI no Dart code can open — and releases the
  /// throwaway copies that resolution makes, however the beam ends.
  ///
  /// Answers false so the ticks survive: a beam takes nothing away and changes
  /// nothing here, so there is no reason for the selection to clear.
  Future<bool> _beamSelected(List<String> keys) async {
    if (keys.isEmpty) return false;
    final List<PrivateImage> selected = _imagesFor(keys);
    if (selected.isEmpty || !mounted) return false;
    final ResolvedBeamFiles
    resolved = await ref.read(resolveBeamFilesProvider).call(<BeamCandidate>[
      // Explicit whichever home it sits in — the vault is the private
      // library's other disk, not a safer tier. See BeamCandidate.
      for (final PrivateImage image in selected) BeamCandidate.ofPrivate(image),
    ]);
    try {
      if (!mounted || resolved.files.isEmpty) return false;
      await BeamSheet.open(context, files: resolved.files);
    } finally {
      // The copies are full-size duplicates of every file sent; a batch of
      // forty left behind is forty wallpapers of cache.
      await resolved.release();
    }
    return false;
  }

  /// The loaded images behind [keys], in the listing's order.
  List<PrivateImage> _imagesFor(List<String> keys) {
    final List<PrivateImage> stored =
        ref.read(privateImagesProvider).value ?? const <PrivateImage>[];
    final Set<String> wanted = keys.toSet();
    return <PrivateImage>[
      for (final PrivateImage image in stored)
        if (wanted.contains(image.ref.key)) image,
    ];
  }

  /// One at a time, counting the ones that failed rather than hiding them:
  /// "deleted 3 of 5" and "deleted 5" are different facts about the device.
  ///
  /// Routes through [deleteDownloadProvider] — the same hard-delete path the
  /// download history and detail screen use (J). For either of the library's
  /// homes that is a file delete plus a history `forget` that no-ops, since
  /// nothing private is ever recorded.
  Future<int> _deleteAll(List<String> keys) async {
    final Map<String, ({StorageTier tier, Uri location})> at = _locationsFor(
      keys,
    );
    int deleted = 0;
    for (final String key in keys) {
      final ({StorageTier tier, Uri location})? found = at[key];
      if (found != null && await _deleteOne(found)) deleted++;
    }
    return deleted;
  }

  /// Where each selected key sits, and in which tier, from the loaded listing.
  ///
  /// **The tier travels with the location**, because the library has two homes:
  /// an app-private file and a vault document delete down entirely different
  /// paths, and a document sent to the app-private delete is a file it cannot
  /// find. See [PrivateImage.tier].
  Map<String, ({StorageTier tier, Uri location})> _locationsFor(
    List<String> keys,
  ) {
    final List<PrivateImage> stored =
        ref.read(privateImagesProvider).value ?? const <PrivateImage>[];
    final Set<String> wanted = keys.toSet();
    return <String, ({StorageTier tier, Uri location})>{
      for (final PrivateImage image in stored)
        if (wanted.contains(image.ref.key))
          image.ref.key: (tier: image.tier, location: image.location),
    };
  }

  Future<bool> _deleteOne(({StorageTier tier, Uri location}) at) async {
    try {
      await ref.read(deleteDownloadProvider)(
        // Neither home records a row: the app-private tier never does, and an
        // explicit wallpaper is refused by the history whatever tier it is in.
        ref: null,
        tier: at.tier,
        location: at.location,
      );
      return true;
    } on ImageStoreFailure {
      return false;
    }
  }

  String _deleteOutcome(AppLocalizations l10n, int deleted, int total) {
    if (deleted == total) return l10n.privateLibraryDeleteDone(total);
    return l10n.privateLibraryDeletePartial(deleted, total, total - deleted);
  }

  Future<bool> _confirmDelete(int count) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.privateLibraryDeleteTitleMany(count)),
        content: Text(l10n.privateLibraryDeleteBodyMany(count)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.privateLibraryDelete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _show(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }
}

/// One private file, decoded from disk rather than from the network.
class _PrivateTile extends StatelessWidget {
  const _PrivateTile({
    required this.image,
    required this.position,
    required this.onTap,
    required this.onLongPress,
    required this.cachedThumbnail,
    required this.onThumbnailResolved,
  });

  final PrivateImage image;
  final int position;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// This image's already-resolved vault thumbnail, if any.
  ///
  /// Null for an app-private image, which never needs one, and for a vault
  /// image whose tile has not finished resolving yet.
  final VaultThumbnail? cachedThumbnail;

  /// Reports a newly-resolved vault thumbnail back up to the screen, so its
  /// aspect ratio can feed the grid's row packing on the next build.
  final void Function(String key, VaultThumbnail thumbnail) onThumbnailResolved;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      image: true,
      // Null outside selection so the tile is not announced as "not selected"
      // in ordinary browsing — the same rule WallpaperTile follows.
      selected: WallpaperSelectionScope.isActive(context)
          ? WallpaperSelectionScope.isSelected(context, image.ref.key)
          : null,
      label: l10n.privateLibraryImageLabel(image.ref.id),
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(wallpaperTileRadius),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        // Sized by the justified row, not here: the row already derived its
        // height from this same ratio (a corrupt file's missing one falls back
        // square there too), and a self-measuring tile would fight it.
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          // The wash-and-tick the shelf shares with every other selectable
          // grid; without it a ticked private tile looked identical to an
          // untouched one.
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _thumbnail(context),
              ?_badge(context),
              WallpaperSelectionOverlay(wallpaperKey: image.ref.key),
            ],
          ),
        ),
      ),
    );
  }

  /// The source pill, in the same corner every other shelf puts it.
  ///
  /// Unconditional here, unlike `WallpaperTile`'s opt-in flag: this grid is
  /// mixed by nature — one folder holding whatever any source sent to the
  /// private tier — so there is no single-source case for it to say nothing in.
  ///
  /// Null when no `WallpaperSourceLabelsScope` names the source: a file written
  /// by a build whose source this one has since retired draws no badge rather
  /// than a raw lowercase id.
  Widget? _badge(BuildContext context) {
    final String? name = WallpaperSourceLabelsScope.labelFor(
      context,
      image.ref.source.value,
    );
    if (name == null) return null;
    return Positioned(
      bottom: 6,
      left: 6,
      child: WallpaperSourceBadge(sourceName: name),
    );
  }

  /// Decodes at roughly tile width, not at the source's 6K. The decoded
  /// thumbnail flies into the secure viewer under a shelf-scoped Hero tag.
  ///
  /// An app-private file is a plain `file:` path, which `Image.file` reads
  /// directly. A vault file is a `content:` SAF document, which it cannot: a
  /// `File` built from anything but a `file:` URI throws before this even
  /// reaches the frame, which is why every vault tile used to render as a
  /// bare grey box in release builds — Flutter's default error widget there
  /// draws nothing else. [_VaultThumbnailImage] resolves that case instead.
  Widget _thumbnail(BuildContext context) {
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final Widget picture = image.tier == StorageTier.filesOutsideGallery
        ? _VaultThumbnailImage(
            image: image,
            cachedThumbnail: cachedThumbnail,
            onResolved: onThumbnailResolved,
            maxDimensionPx: (_tileWidthDip * devicePixelRatio).round(),
          )
        : Image.file(
            File.fromUri(image.location),
            fit: BoxFit.cover,
            cacheWidth: (_tileWidthDip * devicePixelRatio).round(),
            errorBuilder:
                (BuildContext context, Object error, StackTrace? trace) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
          );
    return Hero(
      tag: shelfHeroTag('private-library', image.ref.key, position),
      child: Container(
        foregroundDecoration: wallpaperTileEdge(Theme.of(context).colorScheme),
        child: picture,
      ),
    );
  }

  static const double _tileWidthDip = 200;
}

/// A vault tile's picture: resolved once from its `content:` document, then
/// read straight off the cached path every rebuild after.
///
/// Kept apart from [_PrivateTile] because it is the only part of a tile with
/// anything asynchronous to do — the rest is a plain, stateless build.
class _VaultThumbnailImage extends ConsumerStatefulWidget {
  const _VaultThumbnailImage({
    required this.image,
    required this.cachedThumbnail,
    required this.onResolved,
    required this.maxDimensionPx,
  });

  final PrivateImage image;
  final VaultThumbnail? cachedThumbnail;
  final void Function(String key, VaultThumbnail thumbnail) onResolved;
  final int maxDimensionPx;

  @override
  ConsumerState<_VaultThumbnailImage> createState() =>
      _VaultThumbnailImageState();
}

class _VaultThumbnailImageState extends ConsumerState<_VaultThumbnailImage> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.cachedThumbnail == null) unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final VaultThumbnail? thumbnail = await ref
        .read(localPreviewCacheProvider)
        .materializeThumbnail(widget.image.location, widget.maxDimensionPx);
    if (!mounted) return;
    if (thumbnail == null) {
      setState(() => _failed = true);
      return;
    }
    widget.onResolved(widget.image.ref.key, thumbnail);
  }

  @override
  Widget build(BuildContext context) {
    final VaultThumbnail? thumbnail = widget.cachedThumbnail;
    if (thumbnail == null) {
      if (_failed) {
        return const Center(child: Icon(Icons.broken_image_outlined));
      }
      // Neither loading nor broken — the tile's own Material background shows
      // through until the decode answers, the same neutral wait every image
      // in tela starts from.
      return const SizedBox.expand();
    }
    return Image.file(
      File(thumbnail.path),
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? trace) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
