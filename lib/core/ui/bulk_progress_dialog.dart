import 'dart:async';

import 'package:flutter/material.dart';

/// Shows [work]'s progress in a modal the user cannot dismiss, and answers what
/// [work] answered.
///
/// For a destructive bulk action long enough to look frozen. Deleting a history
/// of hundreds crossed to the platform once and answered only when the last
/// file had settled, so the screen sat there with nothing to say (owner,
/// 2026-07-28).
///
/// **Modal on purpose.** The selection is being consumed as this runs, and a
/// user tapping the same rows again mid-delete would be acting on a list that
/// is already half gone. Blocking is also honest: there is no way to call back
/// a delete already handed to the OS, so an inviting Cancel button would be a
/// lie.
///
/// ```dart
/// final int gone = await showBulkProgress<int>(
///   context: context,
///   label: (int done, int total) => l10n.batchDeleteProgress(done, total),
///   work: (report) => deleteDownloads(records, onProgress: report),
/// );
/// ```
Future<T> showBulkProgress<T>({
  required BuildContext context,
  required String Function(int done, int total) label,
  required Future<T> Function(void Function(int done, int total) report) work,
}) async {
  final _BulkProgress progress = _BulkProgress();
  // Not awaited: the dialog stands until this function pops it, and awaiting
  // it here would block on a route that only closes once the work is done.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) =>
          _BulkProgressDialog(label: label, progress: progress),
    ),
  );
  try {
    return await work(progress.report);
  } finally {
    // `rootNavigator` matches the dialog's own route, and the mounted check
    // covers the tree being torn down under a long delete.
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Fires the dialog's rebuilds without the caller holding a State.
class _BulkProgress extends ChangeNotifier {
  int done = 0;
  int total = 0;

  void report(int done, int total) {
    this.done = done;
    this.total = total;
    notifyListeners();
  }
}

class _BulkProgressDialog extends StatelessWidget {
  const _BulkProgressDialog({required this.label, required this.progress});

  final String Function(int done, int total) label;
  final _BulkProgress progress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back must not leave the work running behind a dismissed dialog.
      canPop: false,
      child: AnimatedBuilder(
        animation: progress,
        builder: (BuildContext context, Widget? _) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(label(progress.done, progress.total)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _fraction),
            ],
          ),
        ),
      ),
    );
  }

  /// Null until the first report, so the bar is indeterminate rather than
  /// sitting at a confident zero while the first chunk is in flight.
  double? get _fraction {
    if (progress.total == 0) return null;
    return progress.done / progress.total;
  }
}
