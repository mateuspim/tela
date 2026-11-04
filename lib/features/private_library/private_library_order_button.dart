import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/domain/models/library_order.dart';
import 'package:tela/features/private_library/private_library_order_controller.dart';

/// Names the private library's order and opens a menu of the two.
///
/// Built like Browse's sorting button: a phone gets the icon alone (see
/// [CapsuleActionCluster.labels]) and the tooltip still names the order.
///
/// ```dart
/// const CapsuleActionCluster(children: <Widget>[PrivateLibraryOrderButton()]);
/// ```
class PrivateLibraryOrderButton extends ConsumerWidget {
  /// Creates the order menu.
  const PrivateLibraryOrderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final LibraryOrder order =
        ref.watch(privateLibraryOrderProvider).value ??
        LibraryOrder.newestFirst;
    final bool labelled = CapsuleActionCluster.labels(context);
    return PopupMenuButton<LibraryOrder>(
      offset: CapsuleActionCluster.menuOffset,
      tooltip: l10n.privateLibraryOrder(orderLabel(l10n, order)),
      initialValue: order,
      onSelected: (LibraryOrder picked) => unawaited(
        ref.read(privateLibraryOrderProvider.notifier).choose(picked),
      ),
      itemBuilder: (BuildContext context) => _items(l10n, order),
      icon: labelled ? null : const Icon(Icons.swap_vert),
      child: labelled ? _label(orderLabel(l10n, order)) : null,
    );
  }

  Widget _label(String current) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[Text(current), const Icon(Icons.arrow_drop_down)],
      ),
    );
  }

  List<PopupMenuEntry<LibraryOrder>> _items(
    AppLocalizations l10n,
    LibraryOrder current,
  ) {
    return <PopupMenuEntry<LibraryOrder>>[
      for (final LibraryOrder order in LibraryOrder.values)
        CheckedPopupMenuItem<LibraryOrder>(
          value: order,
          checked: order == current,
          child: Text(orderLabel(l10n, order)),
        ),
    ];
  }
}

/// The on-screen name of [order].
String orderLabel(AppLocalizations l10n, LibraryOrder order) {
  return switch (order) {
    LibraryOrder.newestFirst => l10n.libraryOrderNewestFirst,
    LibraryOrder.oldestFirst => l10n.libraryOrderOldestFirst,
  };
}
