import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/ports/app_visibility.dart';
import 'package:tela/domain/ports/notification_access.dart';

/// Reports whether tela may post notifications, and opens Android's switch.
///
/// **A row, not a toggle**, because Android gives an app no way to turn its own
/// notifications on or off — see [NotificationAccess]. A `Switch` here could be
/// dragged into a position tela cannot deliver, which is worse than a row that
/// says plainly where the control lives.
///
/// It earns its place in Settings because tela's background work runs *behind*
/// a notification: with these off, an offload the user sent to the background
/// has nothing to show for itself and no way to be stopped from the shade. That
/// had been silently true on the owner's device the whole time (2026-08-25).
class NotificationsTile extends ConsumerWidget {
  /// Creates the notifications row.
  const NotificationsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Unknown reads as off: the row then offers the way to fix it, which is
    // harmless when they were on and the only useful answer when they were not.
    final bool enabled = ref.watch(notificationsEnabledProvider).value ?? false;
    return ListTile(
      key: const Key('settings-notifications'),
      leading: Icon(
        enabled
            ? Icons.notifications_outlined
            : Icons.notifications_off_outlined,
      ),
      title: Text(l10n.settingsNotificationsTitle),
      subtitle: Text(
        enabled ? l10n.settingsNotificationsOn : l10n.settingsNotificationsOff,
      ),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => unawaited(_open(context, ref)),
    );
  }

  /// Opens Android's page, then re-reads the answer once tela is back.
  ///
  /// The wait is what makes the row honest: the user changes the switch in
  /// another app entirely, so without re-reading on return the row would still
  /// be showing the state it had before they left.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppVisibility visibility = ref.read(appVisibilityProvider);
    final bool opened = await ref
        .read(notificationAccessProvider)
        .openSettings();
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsNotificationsUnavailable)),
      );
      return;
    }
    await visibility.whenForeground();
    ref.invalidate(notificationsEnabledProvider);
  }
}
