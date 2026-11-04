import 'package:tela/core/i18n/generated/app_localizations.dart';

/// Renders [duration] the way a progress estimate reads it: `under a minute`,
/// `38 min`, `1 h 5 min`.
///
/// Whole minutes and no seconds. A 50-minute copy that counted down in seconds
/// would claim a precision its estimate does not have, and redraw every time a
/// file landed. Partial minutes round **up**, so "38 min" never turns out to
/// mean 38 minutes and 50 seconds.
///
/// ```dart
/// formatDuration(l10n, const Duration(minutes: 65)); // '1 h 5 min'
/// ```
String formatDuration(AppLocalizations l10n, Duration duration) {
  if (duration < const Duration(minutes: 1)) return l10n.durationUnderMinute;
  final int minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 60) return l10n.durationMinutes(minutes);
  return l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);
}
