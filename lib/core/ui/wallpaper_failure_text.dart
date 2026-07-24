import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/source_failure.dart';

/// Turns a [SourceFailure] into a localized sentence.
///
/// Lives in the UI layer, not the domain: the domain knows *what* failed, the
/// UI decides what to say about it. Exhaustive over the sealed failure type, so
/// a new failure is a compile error here rather than a blank screen.
///
/// In `core/ui` rather than in `browse` because three features now report the
/// same failures, and `core` may not import a feature.
///
/// ```dart
/// Text(localizedFailure(AppLocalizations.of(context), failure));
/// ```
String localizedFailure(AppLocalizations l10n, SourceFailure failure) {
  return switch (failure) {
    InvalidApiKeyFailure() => l10n.errorInvalidApiKey,
    RateLimitedFailure() => l10n.errorRateLimited,
    NetworkFailure() => l10n.errorOffline,
    UnexpectedResponseFailure() => l10n.errorUnexpected,
  };
}
