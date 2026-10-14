import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/broken_image_repair.dart';
import 'package:tela/app/library_listings.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/bulk_progress_dialog.dart';
import 'package:tela/core/ui/tela_toast.dart';
import 'package:tela/domain/models/broken_image.dart';
import 'package:tela/domain/models/repair_tally.dart';
import 'package:tela/domain/models/stored_image_condition.dart';
import 'package:tela/domain/use_cases/find_broken_images.dart';
import 'package:tela/domain/use_cases/repair_broken_images.dart';

/// Finds damaged downloads and, once confirmed, repairs them.
///
/// Counts only, never thumbnails or names: the search reaches the private
/// library too, and this row sits on an ungated screen.
class BrokenImagesTile extends ConsumerWidget {
  /// Creates the row.
  const BrokenImagesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListTile(
      key: const Key('settings-broken-images'),
      leading: const Icon(Icons.healing_outlined),
      title: Text(l10n.brokenImagesTitle),
      subtitle: Text(l10n.brokenImagesDetail),
      onTap: () => _findAndRepair(context, ref),
    );
  }
}

/// Inspect, confirm, repair, report — each step skipped once there is nothing
/// left for it to do.
Future<void> _findAndRepair(BuildContext context, WidgetRef ref) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final List<BrokenImage> broken = await showBulkProgress<List<BrokenImage>>(
    context: context,
    // No count until the listing lands: on a library of thousands that takes
    // seconds, and "Checking 0 of 0" read as stuck (owner, 2026-10-14).
    label: (int done, int total) => total == 0
        ? l10n.brokenImagesListing
        : l10n.brokenImagesChecking(done, total),
    work: (InspectionProgress report) =>
        ref.read(findBrokenImagesProvider)(onProgress: report),
  );
  if (broken.isEmpty) {
    showTelaToast(messenger, l10n.brokenImagesNoneFound);
    return;
  }
  if (!context.mounted || !await _confirm(context, broken)) return;
  if (!context.mounted) return;
  final RepairTally tally = await showBulkProgress<RepairTally>(
    context: context,
    label: l10n.brokenImagesRepairing,
    work: (RepairProgress report) =>
        ref.read(repairBrokenImagesProvider)(broken, onProgress: report),
  );
  refreshDownloads(ref);
  _report(messenger, l10n, tally);
}

Future<bool> _confirm(BuildContext context, List<BrokenImage> broken) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final int empty = broken
      .where((BrokenImage b) => b.condition == StoredImageCondition.empty)
      .length;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.brokenImagesFoundTitle(broken.length)),
      content: Text(
        l10n.brokenImagesFoundBody(empty, broken.length - empty),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.brokenImagesRepairAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void _report(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  RepairTally tally,
) {
  showTelaToast(
    messenger,
    l10n.brokenImagesDone(tally.repaired, tally.removed, tally.failed),
    kind: tally.failed == 0 ? ToastKind.success : ToastKind.failure,
  );
}
