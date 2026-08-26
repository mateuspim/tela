import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/source_failure.dart';

/// What a grid shows when it has no wallpapers to show: an icon, a sentence,
/// and — when there is something to try — one button.
///
/// Every grid in the app reaches this state (browse has no results, favorites
/// is unstarted, the history is empty, the private library is locked), and
/// before this widget each one drew its own centred `Text`. One shape, so
/// "nothing here" reads the same wherever the user meets it.
///
/// ```dart
/// WallpaperStatusView(
///   icon: Icons.favorite_border,
///   message: l10n.favoritesEmpty,
/// );
/// ```
class WallpaperStatusView extends StatelessWidget {
  /// Creates a status view. Without [onAction] it is a statement, not a prompt.
  const WallpaperStatusView({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Reads the failure and says the matching thing: the offline icon for a dead
  /// network, the key icon for a rejected key, and so on.
  ///
  /// Takes `Object?` because that is what a paging controller hands back — a
  /// non-[SourceFailure] is a bug rather than a diagnosis, and gets the
  /// generic wording instead of leaking a stack trace to the user.
  factory WallpaperStatusView.failure({
    required AppLocalizations l10n,
    required Object? error,
    required String sourceName,
    required VoidCallback onRetry,
  }) {
    final SourceFailure? failure = error is SourceFailure ? error : null;
    return WallpaperStatusView(
      icon: failure == null ? Icons.error_outline : _failureIcon(failure),
      message: failure == null
          ? l10n.errorUnexpected
          : localizedFailure(l10n, failure, sourceName: sourceName),
      actionLabel: l10n.actionRetry,
      onAction: onRetry,
    );
  }

  /// Pictogram above the message.
  final IconData icon;

  /// The localized sentence. Never a raw exception.
  final String message;

  /// Label of the single action, if there is one.
  final String? actionLabel;

  /// Called when the action is tapped. Null renders no button.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Centred where there is room, scrollable where there is not. This is a
    // whole-screen state on most shelves, but the Library hub gives its
    // favorites shelf only what its fixed bands leave over, and on a phone that
    // box is shorter than the icon-plus-sentence-plus-button drawn here — it
    // overflowed by 19px (D2b). A status view that cannot be read is worse than
    // one that scrolls, and a `Center` alone cannot do the second.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
            child: ConstrainedBox(
              // An unbounded parent means nobody has said how tall this box
              // is, so there is nothing to centre within — size to content.
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 0,
              ),
              child: _body(context),
            ),
          ),
    );
  }

  Widget _body(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        // Cap the measure: on a 2560-wide tablet an uncapped sentence stretches
        // into one long line the width of the whole shelf, which reads as
        // stranded text rather than a composed empty state. 360 keeps it to a
        // book-column wrap wherever this state is met.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (onAction != null) ...<Widget>[
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel ?? ''),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Exhaustive over the sealed failure, so a new one is a compile error here
  /// rather than a grid that silently falls back to a generic icon.
  static IconData _failureIcon(SourceFailure failure) {
    return switch (failure) {
      InvalidApiKeyFailure() => Icons.key_off_outlined,
      RateLimitedFailure() => Icons.hourglass_empty,
      NetworkFailure() => Icons.cloud_off_outlined,
      NotFoundFailure() => Icons.search_off_outlined,
      // A person-shaped icon, not the generic error one: the fix is naming an
      // account, and the icon is the first hint of that.
      NoCollectionsUsernameFailure() => Icons.person_search_outlined,
      UnexpectedResponseFailure() => Icons.error_outline,
    };
  }
}
