import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';
import 'package:tela/core/ui/duration_text.dart';
import 'package:tela/domain/models/transfer_pace.dart';

/// What a copy in progress has done and has left: share, time, files, bytes,
/// speed.
///
/// The panel used to say only "Moving 1,234 of 7,298…" (owner, 2026-11-04,
/// during a 65 GB move: *"not a progress report or like download speed and how
/// much still needs"*). On a move that runs most of an hour, a bare count is a
/// number that changes without saying whether it will be done by dinner.
///
/// ```dart
/// OffloadCopyReport(run: run);
/// ```
class OffloadCopyReport extends StatelessWidget {
  /// Creates the report over [run], which should be copying.
  const OffloadCopyReport({required this.run, super.key});

  /// The run to describe.
  final OffloadRun run;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TransferPace pace = run.pace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _headline(context, l10n, pace),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: pace.fraction),
        const SizedBox(height: 16),
        _stats(l10n, pace),
      ],
    );
  }

  Widget _headline(
    BuildContext context,
    AppLocalizations l10n,
    TransferPace pace,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    final Duration? left = pace.remaining;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 12,
      children: <Widget>[
        Text(
          l10n.offloadPercentDone((pace.fraction * 100).floor()),
          style: text.headlineSmall,
        ),
        Text(
          left == null
              ? l10n.offloadTimeLeftEstimating
              : l10n.offloadTimeLeft(formatDuration(l10n, left)),
          style: text.bodyMedium,
        ),
      ],
    );
  }

  Widget _stats(AppLocalizations l10n, TransferPace pace) {
    final NumberFormat count = NumberFormat.decimalPattern();
    final String files = l10n.offloadStatOf(
      count.format(run.copied),
      count.format(run.total),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _pair(
          _Stat(label: l10n.offloadStatFiles, value: files),
          _Stat(label: l10n.offloadStatSpeed, value: _speed(l10n, pace)),
        ),
        _pair(
          _Stat(label: l10n.offloadStatData, value: _data(l10n)),
          _Stat(
            label: l10n.offloadStatElapsed,
            value: formatDuration(l10n, run.elapsed),
          ),
        ),
      ],
    );
  }

  Widget _pair(Widget top, Widget bottom) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[top, const SizedBox(height: 12), bottom],
    ),
  );

  /// Copied of total bytes, or a dash for a selection nobody measured.
  String _data(AppLocalizations l10n) {
    if (run.bytes <= 0) return l10n.offloadStatUnknown;
    return l10n.offloadStatOf(
      formatBytes(run.copiedBytes),
      formatBytes(run.bytes),
    );
  }

  /// Bytes a second when the run is measured in bytes; nothing to show for a
  /// files-only pace, whose "per second" is not a speed anyone quotes.
  String _speed(AppLocalizations l10n, TransferPace pace) {
    final double? rate = pace.perSecond;
    if (rate == null) return l10n.offloadStatMeasuring;
    if (run.bytes <= 0) return l10n.offloadStatUnknown;
    return l10n.offloadSpeedValue(formatBytes(rate.round()));
  }
}

/// One labelled figure, label small and muted above the value.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
