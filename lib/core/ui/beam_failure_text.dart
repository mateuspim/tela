import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/beam_failure.dart';

/// Turns a [BeamFailure] into a localized sentence.
///
/// Exhaustive over the sealed failure, so a new one is a compile error here
/// rather than a silent "something went wrong" — the same contract
/// `localizedFailure` has for a wallpaper source.
///
/// [alias] names the machine, because "declined" without a name is ambiguous
/// on a network with two receivers on it.
///
/// ```dart
/// Text(localizedBeamFailure(l10n, failure, alias: target.alias));
/// ```
String localizedBeamFailure(
  AppLocalizations l10n,
  BeamFailure failure, {
  required String alias,
}) {
  return switch (failure) {
    BeamDeclinedFailure() => l10n.beamDeclined(alias),
    BeamBusyFailure() => l10n.beamBusy(alias),
    BeamPinRequiredFailure() => l10n.beamPinRequired(alias),
    BeamUnreachableFailure() => l10n.beamUnreachable,
    BeamExplicitRefusedFailure() => l10n.beamExplicitRefused,
    BeamUnexpectedFailure() => l10n.beamFailed,
  };
}
