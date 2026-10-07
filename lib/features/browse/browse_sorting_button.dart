import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/core/ui/floating_capsule.dart';
import 'package:tela/domain/models/search_query.dart';

/// Names the sorting on screen and opens a menu of the others.
///
/// It replaced a row of sorting tabs under the search capsule. That row cost
/// the wall a full strip of height to show six words most people never touch
/// — the owner, 2026-10-06: *"make this tab be always on latest, then a button
/// reveals it, to not waste all that space"*. The listing still swipes
/// sideways from one sorting to the next, so the tabs' gesture survives them.
///
/// A phone gets the sort icon alone (see [CapsuleActionCluster.labels]); the
/// tooltip still names the sorting there.
///
/// Drives the screen's [TabController] rather than holding a sorting of its
/// own: a swipe and a pick are then the same change, and the label follows
/// either one.
///
/// ```dart
/// BrowseSortingButton(tabs: tabs, sortings: sortings);
/// ```
class BrowseSortingButton extends StatelessWidget {
  /// Creates the menu over [sortings], selecting through [tabs].
  const BrowseSortingButton({
    required this.tabs,
    required this.sortings,
    super.key,
  });

  /// The controller whose index is the sorting on screen.
  final TabController tabs;

  /// The sortings on offer, in the order [tabs] indexes them.
  final List<Sorting> sortings;
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool labelled = CapsuleActionCluster.labels(context);
    return ListenableBuilder(
      listenable: tabs,
      builder: (BuildContext context, Widget? _) {
        final String current = sortingLabel(l10n, sortings[tabs.index]);
        return PopupMenuButton<int>(
          tooltip: l10n.browseSorting(current),
          initialValue: tabs.index,
          onSelected: tabs.animateTo,
          itemBuilder: (BuildContext context) => _items(l10n),
          icon: labelled ? null : const Icon(Icons.sort),
          child: labelled ? _label(current) : null,
        );
      },
    );
  }

  Widget _label(String current) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(current),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  List<PopupMenuEntry<int>> _items(AppLocalizations l10n) {
    return <PopupMenuEntry<int>>[
      for (int index = 0; index < sortings.length; index++)
        CheckedPopupMenuItem<int>(
          value: index,
          checked: index == tabs.index,
          child: Text(sortingLabel(l10n, sortings[index])),
        ),
    ];
  }
}
