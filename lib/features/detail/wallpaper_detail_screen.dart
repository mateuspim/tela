import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/copy_wallpaper_action.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/listing_origin.dart';
import 'package:tela/core/ui/photo_capsule.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/external_link_failure.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/browse/linked_listing_args.dart';
import 'package:tela/features/detail/ambient_wallpaper_tint.dart';
import 'package:tela/features/detail/detail_action_bar.dart';
import 'package:tela/features/detail/detail_apply_button.dart';
import 'package:tela/features/detail/detail_editorial_body.dart';
import 'package:tela/features/detail/detail_preview_pager.dart';
import 'package:tela/features/detail/wallpaper_metadata.dart';
import 'package:tela/features/settings/blocked_tags_providers.dart';

/// Loads complete metadata independently of the grid's fast listing response.
///
/// Keyed by the whole [WallpaperRef], and fetched through *that wallpaper's*
/// source rather than the active one: a favorite opened from the library
/// belongs to whichever site issued it, and an id means nothing anywhere else.
final FutureProviderFamily<WallpaperDetails, WallpaperRef>
wallpaperDetailsProvider = FutureProvider.autoDispose
    .family<WallpaperDetails, WallpaperRef>((
      Ref ref,
      WallpaperRef wallpaper,
    ) {
      final WallpaperSource source = ref.watch(
        wallpaperSourceForProvider(wallpaper.source),
      );
      return source.wallpaperDetails(wallpaper.id);
    });

/// Full-screen preview, metadata, and the shortest path to wallpaper apply.
///
/// The screen itself is a layout and a shelf: it holds the gallery session
/// every part of it reads from, and arranges three pieces that own their own
/// state — [DetailPreviewPager], [DetailActionBar] and [DetailApplyButton] —
/// around the metadata. What is left here is what genuinely belongs to the
/// screen: the one body every width gets — see [DetailEditorialBody] — and
/// where a tag, an uploader or a credit link takes you next.
class WallpaperDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for a grid [wallpaper].
  const WallpaperDetailScreen({
    this.wallpaper,
    this.gallerySession,
    this.originFilters,
    this.originFolder,
    this.immersiveSystemUi = const FlutterImmersiveSystemUi(),
    super.key,
  }) : assert(
         (wallpaper == null) != (gallerySession == null),
         'provide either wallpaper or gallerySession',
       );

  /// The selected wallpaper, including its full-resolution URL.
  final Wallpaper? wallpaper;

  /// An ordered shelf snapshot. Its creator retains disposal ownership.
  final GallerySessionController<Wallpaper>? gallerySession;

  /// The filters of the listing this detail was opened from, forwarded to any
  /// tag or uploader followed from here so the drill-down inherits the world
  /// the user was already in — sketchy stays sketchy — rather than resetting to
  /// Browse's own. Null when the shelf had no filters to inherit (Favorites,
  /// History, a deep link), which falls back to Browse, as it always did.
  final SearchQuery? originFilters;

  /// The folder that listing names, when [originFilters] cannot spell it.
  /// Republished below as a `ListingOrigin`, because a pushed route inherits
  /// none of the shelf's scopes and the download button has to know which
  /// listing it is filing from.
  final TagFolder? originFolder;

  /// The Android system-chrome seam used by the immersive preview.
  final ImmersiveSystemUi immersiveSystemUi;

  @override
  ConsumerState<WallpaperDetailScreen> createState() =>
      _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends ConsumerState<WallpaperDetailScreen> {
  late final GallerySessionController<Wallpaper> _gallery;
  late final bool _ownsGallery;

  /// The handle on the facts sheet, held here because two widgets this screen
  /// builds need it and neither can reach the other: the sheet lives inside
  /// [DetailEditorialBody], and the upward throw that opens it is measured on
  /// [DetailPreviewPager], which that body is merely handed.
  final DraggableScrollableController _sheet = DraggableScrollableController();

  Wallpaper get _wallpaper => _gallery.selectedItem;

  @override
  void initState() {
    super.initState();
    _ownsGallery = widget.gallerySession == null;
    _gallery =
        widget.gallerySession ??
        GallerySessionController<Wallpaper>(
          identity: 'wallpaper:${widget.wallpaper!.id}',
          items: <Wallpaper>[widget.wallpaper!],
          initialIndex: 0,
        );
    _gallery.addListener(_selectionChanged);
  }

  /// Keeps the rest of the screen on the session's selection, whichever moved
  /// it — a swipe in the pager, a chevron, or the fullscreen viewer paging the
  /// shared session while Detail sits behind it. The pager keeps *itself* in
  /// step; this is only about the metadata and the actions below it.
  void _selectionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _gallery.removeListener(_selectionChanged);
    if (_ownsGallery) _gallery.dispose();
    _sheet.dispose();
    super.dispose();
  }

  /// Pushes the listing behind a tag or an uploader, rather than replacing this
  /// one, so Back returns to the wallpaper the link was printed on and the
  /// browse tabs are left exactly as the user had them.
  void _follow(WallpaperLink link) {
    unawaited(
      context.pushNamed(
        TelaRoutes.linkedListingName,
        extra: LinkedListingArgs(link: link, seed: widget.originFilters),
      ),
    );
  }

  /// Hands a URL — a wallpaper's credit or its source page — to the device
  /// browser, saying so only when nothing can open it.
  Future<void> _openLink(Uri url) async {
    try {
      await ref.read(externalLinkProvider).open(url);
    } on ExternalLinkFailure {
      if (mounted) {
        _showResult(
          AppLocalizations.of(context).detailLinkFailure,
          kind: ToastKind.failure,
        );
      }
    }
  }

  void _showResult(String message, {ToastKind kind = ToastKind.success}) {
    showTelaToast(ScaffoldMessenger.of(context), message, kind: kind);
  }

  /// Asks before blocking a tag — every future search silently excludes it,
  /// which is not a thing to do on a single stray long press. Mirrors the
  /// download-history "Remove from history?" dialog: say plainly what will
  /// happen, and that it can be undone.
  Future<void> _confirmBlockTag(WallpaperTag tag) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.detailTagBlockTitle),
        content: Text(l10n.detailTagBlockBody(tag.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.detailTagBlock),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _blockTag(tag);
  }

  Future<void> _blockTag(WallpaperTag tag) async {
    await ref.read(tagBlocklistRepositoryProvider).block(tag);
    refreshBlockedTags(ref);
    if (mounted) {
      _showResult(AppLocalizations.of(context).detailTagBlocked(tag.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<WallpaperDetails> details = ref.watch(
      wallpaperDetailsProvider(_wallpaper.ref),
    );
    final String sourceName = ref
        .watch(wallpaperSourceForProvider(_wallpaper.source))
        .displayName;
    // There was a `Builder` between these two, so that the wide layout's
    // information pane — which read `Theme.of` in `_expandedBody`, on this
    // State's own context, outside the theme this method returns — resolved
    // below the tint instead of beside it. That pane is gone, and with it the
    // only caller that read a theme up here: everything left resolves its own
    // context, which is already under this widget. Measured before removing
    // it (2026-08-15): with the Builder in place the block-tag dialog is
    // *untinted* either way, because `showDialog` captures from this State's
    // context, which no Builder inside `build` can move.
    return AmbientWallpaperTint(
      wallpaper: _wallpaper,
      child: _listed(_screen(details, l10n, sourceName)),
    );
  }

  /// Republishes the listing this screen was opened from.
  ///
  /// A pushed route is built under the Navigator, so it inherits nothing from
  /// the shelf that pushed it — the same reason `AmbientWallpaperTint` wraps
  /// this screen rather than being inherited from the wall. A shelf with no
  /// filters to hand over (Favorites, the download history, a deep link)
  /// publishes nothing, and the download button then suggests only the
  /// remembered tag, which is the honest answer there.
  Widget _listed(Widget screen) {
    final SearchQuery? filters = widget.originFilters;
    if (filters == null) return screen;
    return ListingOrigin(
      filters: filters,
      folder: widget.originFolder,
      child: screen,
    );
  }

  Widget _screen(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
    String sourceName,
  ) {
    return Scaffold(
      // The layout runs the wallpaper to every edge at every width, so the bar
      // stops reserving space and floats over it instead.
      extendBodyBehindAppBar: true,
      // No title: the resolution that used to sit here is a spec, not a name,
      // and it already has a tile in the Details grid — a title bar reading
      // "2880x1800" labelled the screen with a number. The image is the
      // subject, so the bar carries only the back affordance and the actions.
      appBar: _floatingBar(),
      body: _body(details, l10n, sourceName),
    );
  }

  /// The bar that sits *on* the wallpaper rather than above it.
  ///
  /// Transparent, with its controls forced white and read against the scrim
  /// `DetailEditorialBody` paints behind them. **This is not A2's frosted
  /// bar**: nothing here is blurred, and what shows through is the single
  /// photograph the screen is about, not a wall of sixty competing with the
  /// chrome. That was the whole objection, and it does not apply.
  ///
  /// Back and the actions each ride a [PhotoCapsule]: the scrim alone gave
  /// them nothing to sit on once the sheet rose to full and the icons landed
  /// bare on the facts (device survey, 2026-10-05), and the capsule is the
  /// same shape the rest of the app's chrome now floats in.
  PreferredSizeWidget _floatingBar() {
    final bool canGoBack =
        ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      // Inset 12 from the edge, mirroring the actions' trailing gap.
      leadingWidth: 72,
      leading: canGoBack
          ? const Padding(
              padding: EdgeInsetsDirectional.only(start: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: PhotoCapsule(child: BackButton()),
              ),
            )
          : null,
      actions: <Widget>[
        PhotoCapsule(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DetailActionBar(wallpaper: _wallpaper),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  /// The layout, at every width: the wallpaper is the page, the facts ride
  /// over it on a sheet.
  ///
  /// There used to be a second, two-pane body above 840dp. It was retired on
  /// 2026-08-14 by the owner, after driving both on the tablet — see
  /// [DetailEditorialBody], which carries the argument the pane once won and
  /// what beat it.
  Widget _body(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
    String sourceName,
  ) {
    return DetailEditorialBody(
      preview: _preview(),
      metadata: _metadata(details, l10n, sourceName),
      applyButton: DetailApplyButton(wallpaper: _wallpaper),
      sheetController: _sheet,
    );
  }

  Widget _preview() {
    return DetailPreviewPager(
      gallery: _gallery,
      systemUi: widget.immersiveSystemUi,
      onHoldImage: _copyToClipboard,
      onRevealDetails: _revealDetails,
    );
  }

  /// Raises the facts sheet, for a finger that threw the wallpaper upward.
  ///
  /// The gesture reaches the whole picture, which is the point: the grip is a
  /// 48dp band at the very foot of the screen and the wallpaper above it is
  /// everything else. The sheet's own handle stays — a throw is invisible to a
  /// screen reader, so it is never the only way in.
  void _revealDetails() {
    unawaited(
      DetailEditorialBody.revealSheet(
        _sheet,
        animate: !MediaQuery.disableAnimationsOf(context),
      ),
    );
  }

  /// Holding the wallpaper copies it, the gesture equivalent of the share
  /// sheet's *Copy image* — the fastest way out of tela and into whatever app
  /// the user meant to paste it in. The pager withholds it for an explicit
  /// wallpaper on its own; nothing about that rule is decided here.
  void _copyToClipboard(Wallpaper wallpaper) {
    unawaited(
      copyWallpaperToClipboard(
        context: context,
        ref: ref,
        wallpaper: wallpaper,
      ),
    );
  }

  Widget _metadata(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
    String sourceName,
  ) {
    return details.when(
      data: (WallpaperDetails value) => WallpaperMetadata(
        details: value,
        sourceName: sourceName,
        onFollow: _follow,
        onBlockTag: _confirmBlockTag,
        onOpenLink: _openLink,
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error is SourceFailure
              ? localizedFailure(l10n, error, sourceName: sourceName)
              : l10n.errorUnexpected,
        ),
      ),
    );
  }
}
