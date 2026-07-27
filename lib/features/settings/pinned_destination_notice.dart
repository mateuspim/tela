import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/pinned_download_tier.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_tier_text.dart';
import 'package:tela/domain/models/storage_tier.dart';

/// Says a "Keep sending here" pin is in force, and offers to stop it.
///
/// **The screen this feature was missing.** The pin's whole job is to silence
/// the destination chooser — once set, the quick sheet, the batch bar and the
/// detail screen all route silently — so it is the one setting the user stops
/// being shown at the moment it starts working. It presented as "downloading
/// doesn't ask me where any more" with nothing on any screen to explain it, and
/// the only way out was long-pressing Download on a wallpaper's detail screen
/// and finding *Stop* inside the chooser (owner, 2026-07-27).
///
/// Renders nothing when no pin is set: an empty row saying "no pin" would be a
/// permanent explanation of a feature most users never turn on.
class PinnedDestinationNotice extends ConsumerWidget {
  /// Creates the notice.
  const PinnedDestinationNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StorageTier? pin = ref.watch(pinnedDownloadTierProvider).value;
    if (pin == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        // The one tinted-container in this group that is *not* the recessed
        // panel: this reports a state the user may not know they are in, so it
        // reads as a notice rather than as another nested control.
        color: theme.colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(
            Icons.push_pin_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          title: Text(l10n.downloadPinActive(storageTierLabel(l10n, pin))),
          subtitle: Text(l10n.settingsDownloadPinHelp),
          trailing: TextButton(
            key: const Key('settings-stop-download-pin'),
            onPressed: () =>
                ref.read(pinnedDownloadTierProvider.notifier).clear(),
            child: Text(l10n.downloadPinStop),
          ),
        ),
      ),
    );
  }
}
