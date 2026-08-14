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
import 'package:tela/core/ui/ambient_wallpaper_theme.dart';
import 'package:tela/core/ui/backdrop_drift_scope.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/core/ui/immersive_system_ui.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/ambient_seed.dart';
import 'package:tela/domain/models/external_link_failure.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/browse/linked_listing_args.dart';
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

/// The colour a wallpaper's own pixels are mostly made of, for tinting.
///
/// Keyed by thumbnail URL rather than by wallpaper, so two shelves showing the
/// same image share one read. Only ever watched for a source that reported no
/// palette — see `_ambientFallback` — so Wallhaven never spends a decode on a
/// question its own JSON already answered.
final FutureProviderFamily<WallpaperColor?, String> ambientFallbackProvider =
    FutureProvider.autoDispose.family<WallpaperColor?, String>(
      (Ref ref, String thumbnailUrl) =>
          ref.watch(dominantColorProvider).of(thumbnailUrl),
    );

/// Full-screen preview, metadata, and the shortest path to wallpaper apply.
///
/// The screen itself is a layout and a shelf: it holds the gallery session
/// every part of it reads from, and arranges three pieces that own their own
/// state — [DetailPreviewPager], [DetailActionBar] and [DetailApplyButton] —
/// around the metadata. What is left here is what genuinely belongs to the
/// screen: which body the width gets, and where a tag, an uploader or a credit
/// link takes you next.
class WallpaperDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for a grid [wallpaper].
  const WallpaperDetailScreen({
    this.wallpaper,
    this.gallerySession,
    this.originFilters,
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

  /// The Android system-chrome seam used by the immersive preview.
  final ImmersiveSystemUi immersiveSystemUi;

  @override
  ConsumerState<WallpaperDetailScreen> createState() =>
      _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends ConsumerState<WallpaperDetailScreen> {
  late final GallerySessionController<Wallpaper> _gallery;
  late final bool _ownsGallery;

  /// How far the wide layout's blurred scenery has drifted, -1..1.
  ///
  /// The phone layout owns its own — `DetailEditorialBody` drives that one off
  /// the sheet. This is the tablet's driver, and it is a different gesture on
  /// purpose: there the facts are a *pane*, and scrolling it is the only motion
  /// the screen has.
  final ValueNotifier<double> _paneDrift = ValueNotifier<double>(0);

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
    _paneDrift.dispose();
    if (_ownsGallery) _gallery.dispose();
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
    // The tint sits *above* the Scaffold, and the Builder is what puts the
    // screen beneath it rather than beside it: the panes below read
    // `Theme.of` off this State's own context, which is outside the theme
    // this method returns, so without it only the widgets deep enough to
    // resolve their own would move and the surfaces would stay behind.
    return AmbientWallpaperTheme(
      colors: _wallpaper.colors,
      fallbackSeed: _ambientFallback(),
      child: Builder(
        builder: (BuildContext context) =>
            _screen(context, details, l10n, sourceName),
      ),
    );
  }

  /// A colour read from the wallpaper itself, for a source that reports none.
  ///
  /// Watched only when there is nothing to read from the listing, so Wallhaven
  /// — which answers this in its own JSON — never decodes a pixel for it. The
  /// read is asynchronous, so the screen paints untinted for the frames it
  /// takes and arrives at its colour a beat later; that beat is why this is a
  /// fallback and not the primary path.
  WallpaperColor? _ambientFallback() {
    if (ambientSeed(_wallpaper.colors) != null) return null;
    return ref
        .watch(ambientFallbackProvider(_wallpaper.thumbOriginalUrl))
        .value;
  }

  Widget _screen(
    BuildContext context,
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
    String sourceName,
  ) {
    final bool expanded = MediaQuery.sizeOf(context).width >= _expandedWidth;
    return Scaffold(
      // The narrow layout runs the wallpaper to every edge, so the bar stops
      // reserving space and floats over it instead. The wide one still has a
      // pane of its own and keeps an ordinary bar above it.
      extendBodyBehindAppBar: !expanded,
      // No title: the resolution that used to sit here is a spec, not a name,
      // and it already has a tile in the Details grid — a title bar reading
      // "2880x1800" labelled the screen with a number. The image is the
      // subject, so the bar carries only the back affordance and the actions.
      appBar: expanded ? AppBar() : _floatingBar(),
      body: expanded
          ? _expandedBody(context, details, l10n, sourceName)
          : _compactBody(details, l10n, sourceName),
    );
  }

  /// The bar that sits *on* the wallpaper rather than above it.
  ///
  /// Transparent, with its controls forced white and read against the scrim
  /// `DetailEditorialBody` paints behind them. **This is not A2's frosted
  /// bar**: nothing here is blurred, and what shows through is the single
  /// photograph the screen is about, not a wall of sixty competing with the
  /// chrome. That was the whole objection, and it does not apply.
  PreferredSizeWidget _floatingBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
      actions: <Widget>[DetailActionBar(wallpaper: _wallpaper)],
    );
  }

  static const double _expandedWidth = 840;

  /// The phone layout: the wallpaper is the page, the facts ride over it.
  ///
  /// Replaced a fixed-height preview stacked above a scrolling panel, where the
  /// image was a picture in a box on the one screen whose subject *is* the
  /// image. See [DetailEditorialBody] — including why the wide layout
  /// deliberately did not follow.
  Widget _compactBody(
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
    String sourceName,
  ) {
    return DetailEditorialBody(
      preview: _preview(),
      metadata: _metadata(details, l10n, sourceName),
      applyButton: DetailApplyButton(wallpaper: _wallpaper),
    );
  }

  /// Takes [context] rather than reading this State's own: the information
  /// pane paints itself from the scheme, and on this screen that scheme is the
  /// wallpaper's — which only exists below the ambient theme.
  Widget _expandedBody(
    BuildContext context,
    AsyncValue<WallpaperDetails> details,
    AppLocalizations l10n,
    String sourceName,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return BackdropDriftScope(
      drift: _paneDrift,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  key: const Key('detail-preview-pane'),
                  color: Colors.black,
                  child: _preview(),
                ),
              ),
            ),
          ),
          SizedBox(
            key: const Key('detail-information-pane'),
            width: 440,
            child: ColoredBox(
              color: colors.surfaceContainerLow,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: DetailActionBar(
                      wallpaper: _wallpaper,
                      expanded: true,
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _paneScrolled,
                      child: SingleChildScrollView(
                        child: _metadata(details, l10n, sourceName),
                      ),
                    ),
                  ),
                  DetailApplyButton(wallpaper: _wallpaper),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// How far the information pane must scroll for the scenery to drift fully.
  ///
  /// A distance rather than a fraction of the pane's content, so the scenery
  /// moves at the same *rate* whatever the wallpaper's metadata happens to
  /// weigh — a picture with forty tags would otherwise drift a tenth as fast as
  /// one with two, for the same finger travel.
  static const double _paneDriftSpan = 600;

  /// Drifts the scenery up as the facts beside it are scrolled up.
  ///
  /// Reads the notification rather than owning a `ScrollController`: the pane's
  /// scroll view builds its own, and taking that over would mean disposing a
  /// controller for an effect that is pure decoration.
  ///
  /// Returns false so the notification carries on up the tree.
  bool _paneScrolled(ScrollNotification pane) {
    if (pane.depth > 0) return false;
    _paneDrift.value = -(pane.metrics.pixels / _paneDriftSpan).clamp(0.0, 1.0);
    return false;
  }

  Widget _preview() {
    return DetailPreviewPager(
      gallery: _gallery,
      systemUi: widget.immersiveSystemUi,
      onHoldImage: _copyToClipboard,
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
