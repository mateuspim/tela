import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';

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
  /// non-[WallhavenFailure] is a bug rather than a diagnosis, and gets the
  /// generic wording instead of leaking a stack trace to the user.
  factory WallpaperStatusView.failure({
    required AppLocalizations l10n,
    required Object? error,
    required VoidCallback onRetry,
  }) {
    final WallhavenFailure? failure = error is WallhavenFailure ? error : null;
    return WallpaperStatusView(
      icon: failure == null ? Icons.error_outline : _failureIcon(failure),
      message: failure == null
          ? l10n.errorUnexpected
          : localizedFailure(l10n, failure),
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
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.outline),
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
    );
  }

  /// Exhaustive over the sealed failure, so a new one is a compile error here
  /// rather than a grid that silently falls back to a generic icon.
  static IconData _failureIcon(WallhavenFailure failure) {
    return switch (failure) {
      InvalidApiKeyFailure() => Icons.key_off_outlined,
      RateLimitedFailure() => Icons.hourglass_empty,
      NetworkFailure() => Icons.cloud_off_outlined,
      UnexpectedResponseFailure() => Icons.error_outline,
    };
  }
}
