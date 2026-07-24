import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/features/favorites/favorites_providers.dart';

/// The heart that keeps a wallpaper, on the detail screen's app bar.
class FavoriteButton extends ConsumerWidget {
  /// Creates the toggle for [wallpaper].
  const FavoriteButton({required this.wallpaper, super.key});

  /// The wallpaper being favorited or un-favorited.
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // An unresolved read renders the empty heart rather than a spinner: the
    // answer arrives in a frame or two from local SQLite, and a flicker of
    // progress indicator in an app bar is worse than an outline that fills in.
    final bool isFavorite =
        ref.watch(isFavoriteProvider(wallpaper.ref)).value ?? false;

    return IconButton(
      icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
      tooltip: isFavorite ? l10n.favoriteRemove : l10n.favoriteAdd,
      onPressed: () => _toggle(ref),
    );
  }

  Future<void> _toggle(WidgetRef ref) async {
    await ref.read(toggleFavoriteProvider)(wallpaper);
    refreshFavorites(ref, wallpaper.ref);
  }
}
