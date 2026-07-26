import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/browse/browse_search_draft.dart';

/// Offers to open the wallpaper whose id is currently typed in the search box.
///
/// An offer, never an interception: pressing Enter still runs an ordinary text
/// search, so a real six-character search term is never hijacked, and the
/// affordance is visible rather than a hidden gesture someone has to know
/// about. It appears only when the *active* source recognizes the text as one
/// of its own ids — Wallhaven's six characters, Konachan's post number — so a
/// source that cannot recognize its ids simply never offers it.
///
/// The pattern only decides whether to offer. Whether the wallpaper exists is
/// settled by the API on tap, and a miss says so instead of navigating.
///
/// Lives **inside the search field**, as its `suffix`. Two earlier placements
/// were tried on the owner's tablet and both were wrong, so do not move it back
/// without a device pass:
///
/// 1. *App bar, above the tabs* — shoved the whole tab row down mid-typing, ate
///    scarce vertical space, was easy to miss, and read as belonging to the
///    tabs rather than to the search box.
/// 2. *Floating over the grid* — fixed the shoving, but landed squarely on the
///    first thumbnail, so it read as a tooltip stuck onto someone's wallpaper.
///
/// In the field it covers nothing, sits beside the text it refers to, and uses
/// space that was empty anyway: on a tablet the field is ~1400px wide and a
/// six-character id fills about 7% of it.
///
/// Keeping the id in the label is deliberate even though the field shows it a
/// centimetre away — the label carries the **normalized** id, so typing
/// `Qrlwql` and being offered `qrlwql` is how someone sees which id will
/// actually be fetched.
///
/// ```dart
/// TextField(
///   decoration: const InputDecoration(suffix: WallpaperIdChip()),
/// );
/// ```
class WallpaperIdChip extends ConsumerStatefulWidget {
  /// Creates the id-jump chip.
  const WallpaperIdChip({super.key});

  @override
  ConsumerState<WallpaperIdChip> createState() => _WallpaperIdChipState();
}

class _WallpaperIdChipState extends ConsumerState<WallpaperIdChip> {
  bool _looking = false;

  @override
  Widget build(BuildContext context) {
    final String? id = ref.watch(browseDraftWallpaperIdProvider);
    // Shrinks away rather than being unmounted, so the field's own height —
    // and therefore the tab row below it — never moves as this comes and goes.
    if (id == null) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = l10n.browseGoToWallpaper(id);
    // Null while a lookup is in flight, so a second tap cannot push the detail
    // route twice.
    final VoidCallback? onPressed = _looking ? null : () => _jumpTo(id);
    // A phone's field has no room for the sentence a tablet's does; the icon
    // keeps the same action reachable rather than dropping it below some width.
    final bool roomy = MediaQuery.sizeOf(context).width >= _labelWidth;
    if (!roomy) {
      return IconButton(
        icon: _icon,
        tooltip: label,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      );
    }
    return ActionChip(
      avatar: _icon,
      label: Text(label),
      onPressed: onPressed,
      // Compact and shrink-wrapped: a default-density chip is taller than the
      // text it sits beside and would stretch the field around it.
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// Below this width the label is dropped for the icon alone.
  static const double _labelWidth = 600;

  Widget get _icon => _looking
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.arrow_forward, size: 18);

  /// Fetches [id] through the active source and opens it, or explains why not.
  Future<void> _jumpTo(String id) async {
    final WallpaperSource source = ref.read(activeWallpaperSourceProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final GoRouter router = GoRouter.of(context);
    setState(() => _looking = true);
    try {
      final WallpaperDetails details = await source.wallpaperDetails(id);
      if (!mounted) return;
      // A bare Wallpaper: the detail screen wraps it in its own one-item
      // gallery, so a jump needs no session and nothing to dispose here.
      await router.pushNamed<void>(
        TelaRoutes.detailName,
        pathParameters: <String, String>{
          'wallpaperKey': details.wallpaper.ref.key,
        },
        extra: details.wallpaper,
      );
    } on SourceFailure catch (failure) {
      showTelaToast(
        messenger,
        localizedFailure(l10n, failure, sourceName: source.displayName),
        kind: ToastKind.failure,
      );
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }
}
