/// What the wall shows when it is not showing wallpapers.
///
/// Three states with one thing in common — they are all the paging state made
/// visible — kept apart from the grid that owns the paging so that "how a
/// listing looks while it is empty, loading or broken" can be read in one
/// place.
///
/// ```dart
/// footer: wallFooter(l10n, state, sourceName: name, onRetry: _retry)
/// ```
library;

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_grid_skeleton.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/wallpaper.dart';

/// What sits below the last row: nothing, a next-page spinner, or a retry.
Widget? wallFooter(
  AppLocalizations l10n,
  PagingState<int, Wallpaper> state, {
  required String sourceName,
  required VoidCallback onRetry,
}) {
  if (state.error != null) {
    return wallFailure(
      l10n,
      state.error,
      sourceName: sourceName,
      onRetry: onRetry,
    );
  }
  if (!state.isLoading) return null;
  return const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: CircularProgressIndicator()),
  );
}

/// The whole-screen state before any wallpaper has arrived.
///
/// Kept scrollable so pull-to-refresh still works when there is nothing to
/// scroll — a listing that came back empty or failed is exactly when the user
/// reaches for it, and [RefreshIndicator] ignores a non-scrolling child.
Widget wallFirstPage(
  AppLocalizations l10n,
  PagingState<int, Wallpaper> state, {
  required String sourceName,
  required VoidCallback onRetry,
}) {
  final Widget body = switch (state) {
    PagingState<int, Wallpaper>(error: final Object error?) => wallFailure(
      l10n,
      error,
      sourceName: sourceName,
      onRetry: onRetry,
    ),
    PagingState<int, Wallpaper>(isLoading: true) =>
      const WallpaperGridSkeleton(),
    _ => WallpaperStatusView(icon: Icons.search_off, message: l10n.browseEmpty),
  };
  return LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) =>
        SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Exactly the viewport's height, not a minimum: the skeleton packs
          // its rows against a bounded box and overruns it deliberately, so
          // an unbounded child here makes it size to infinity and throw.
          child: SizedBox(height: constraints.maxHeight, child: body),
        ),
  );
}

/// The failure the source reported, in its own words, with a way to try again.
Widget wallFailure(
  AppLocalizations l10n,
  Object? error, {
  required String sourceName,
  required VoidCallback onRetry,
}) {
  return WallpaperStatusView.failure(
    l10n: l10n,
    error: error,
    sourceName: sourceName,
    onRetry: onRetry,
  );
}
