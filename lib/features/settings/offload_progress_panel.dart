import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/app/offload_run_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';

/// Reports the offload that is running, in the page rather than over it.
///
/// **Replaces a modal that could not be dismissed**, and the swap is the whole
/// feature: the move now outlives this screen, so the one thing the UI must not
/// do is imply otherwise. The panel says so in words as well as by being
/// leaveable.
class OffloadProgressPanel extends ConsumerWidget {
  /// Creates the panel over the run in [offloadRunProvider].
  const OffloadProgressPanel({required this.run, super.key});

  /// The run to describe.
  final OffloadRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_heading(l10n), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _fraction()),
            const SizedBox(height: 12),
            Text(_line(l10n), style: theme.textTheme.bodyMedium),
            ..._tail(context, ref, l10n, theme),
          ],
        ),
      ),
    );
  }

  String _heading(AppLocalizations l10n) =>
      run.isDone ? l10n.offloadTitle : l10n.offloadRunning;

  /// A position while copying, full once it is over, and **indeterminate in
  /// between** — which is the honest reading of each.
  ///
  /// The middle phases have no position to report: removing the originals is
  /// one call, and waiting for a screen is waiting on the user. A bar frozen at
  /// 100% through either reads as a hang. A finished run is the opposite case:
  /// it is not working, so a bar that keeps sweeping says it is.
  double? _fraction() {
    if (run.isDone) return 1;
    if (!run.isCopying || run.total == 0) return null;
    return run.copied / run.total;
  }

  String _line(AppLocalizations l10n) {
    if (run.stopping && !run.isDone) return l10n.offloadStopping;
    return switch (run.phase) {
      OffloadPhase.copying => l10n.offloadProgress(run.copied, run.total),
      OffloadPhase.waitingForScreen => l10n.offloadWaitingForScreen,
      OffloadPhase.removing => l10n.offloadFinishing,
      OffloadPhase.done => _outcome(l10n),
    };
  }

  String _outcome(AppLocalizations l10n) {
    if (run.failed) return l10n.moveFailure;
    if (run.stopping) return l10n.offloadStopped(run.moved);
    if (run.isComplete) {
      return l10n.offloadDone(run.moved, formatBytes(run.bytes));
    }
    return l10n.offloadPartial(run.moved, run.total);
  }

  /// Confirms what actually changed for future downloads, once at least one
  /// file made the trip — the same condition `OffloadRunController._reroute`
  /// uses, so this never claims a switch that did not happen.
  ///
  /// Null for a run that moved nothing: the pre-move copy already promised
  /// this, and a run with zero successes has nothing to confirm.
  Widget? _futureDownloadsNotice(AppLocalizations l10n, ThemeData theme) {
    if (run.moved == 0) return null;
    final String text = run.includesPrivateLibrary
        ? l10n.offloadDoneFutureDownloadsExplicit
        : l10n.offloadDoneFutureDownloads;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// The reassurance while it runs, and the way to dismiss it once it has.
  List<Widget> _tail(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (run.isDone) {
      return <Widget>[
        ?_futureDownloadsNotice(l10n, theme),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('offload-acknowledge'),
            onPressed: () =>
                ref.read(offloadRunProvider.notifier).acknowledge(),
            child: Text(l10n.actionDone),
          ),
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: 8),
      Text(
        l10n.offloadLeaveFreely,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          key: const Key('offload-stop'),
          onPressed: run.stopping
              ? null
              : () => ref.read(offloadRunProvider.notifier).stop(),
          child: Text(l10n.offloadStop),
        ),
      ),
    ];
  }
}
