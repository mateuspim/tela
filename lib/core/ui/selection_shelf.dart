import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_selection.dart';

/// One thing the contextual bar can do to every ticked item.
///
/// Deliberately domain-free — an icon, a label, and a callback taking ids — so
/// this file stays in `core/ui`, which holds no Riverpod and no domain types.
/// The wallpaper shelves and the private library each map their own batch
/// actions onto these, which is what lets both share one bar.
class SelectionAction {
  /// Creates an action shown as one icon button in the bar.
  const SelectionAction({
    required this.icon,
    required this.label,
    required this.run,
  });

  /// The bar's icon for this action.
  final IconData icon;

  /// Tooltip and accessibility label.
  final String label;

  /// Performs the action, answering whether it ran — false when a confirmation
  /// was declined, so the ticks survive a cancelled dialog.
  final Future<bool> Function(List<String> selectedIds) run;
}

/// Owns one screen's selection and puts it above that screen's [Scaffold].
///
/// **The placement is the whole point.** The selection has to be readable both
/// by the tiles (below the shelf) and by a *Select* button in the app bar
/// (above the body), and an `InheritedWidget` only reaches downwards — so it
/// has to sit above the `Scaffold` rather than around the grid. Wrapping only
/// the grid is what made an app-bar entry impossible in the first version.
///
/// Also hosts the [PopScope]: back leaves selection before it leaves the
/// screen, which is the first gesture anyone tries to undo a selection.
///
/// ```dart
/// SelectionShelfScope(
///   child: Scaffold(
///     appBar: AppBar(actions: <Widget>[SelectModeButton()]),
///     body: SelectionShelf(itemIds: ids, actions: actions, child: grid),
///   ),
/// );
/// ```
class SelectionShelfScope extends StatefulWidget {
  /// Publishes a fresh selection to everything under [child].
  const SelectionShelfScope({required this.child, super.key});

  /// The screen this selection belongs to, `Scaffold` and all.
  final Widget child;

  @override
  State<SelectionShelfScope> createState() => _SelectionShelfScopeState();
}

class _SelectionShelfScopeState extends State<SelectionShelfScope> {
  final WallpaperSelection _selection = WallpaperSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WallpaperSelectionScope(
      selection: _selection,
      child: ListenableBuilder(
        listenable: _selection,
        builder: (BuildContext context, Widget? child) => PopScope(
          canPop: !_selection.isActive,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) _selection.clear();
          },
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}

/// The app-bar action that starts selecting, with nothing ticked yet.
///
/// Hidden while already selecting: the contextual bar owns the screen then, and
/// a second way in beside a *Cancel* reads as a second mode. Renders nothing at
/// all with no [SelectionShelfScope] above it, so a screen that has not opted
/// in cannot show a button that does nothing.
class SelectModeButton extends StatelessWidget {
  /// Creates the *Select* app-bar action.
  const SelectModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final WallpaperSelection? selection = WallpaperSelectionScope.of(context);
    if (selection == null || selection.isActive) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.checklist),
      tooltip: AppLocalizations.of(context).quickActionSelect,
      onPressed: selection.enter,
    );
  }
}

/// A shelf that grows a contextual bar above it while its screen is selecting.
///
/// The bar is a band above the grid rather than a floating bottom bar or a
/// swapped app bar: some shelves are embedded widgets with no app bar of their
/// own, and others sit above a bottom navigation bar a floating bar would
/// fight, so the band is the one position that works everywhere without each
/// shelf special-casing itself.
class SelectionShelf extends StatelessWidget {
  /// Wraps [child], offering [actions] over the ticked subset of [itemIds].
  const SelectionShelf({
    required this.itemIds,
    required this.actions,
    required this.child,
    this.expandChild = true,
    super.key,
  });

  /// Every item the shelf is showing, in the order it shows them. Selection is
  /// resolved against this, so an id that leaves the listing stops counting.
  final List<String> itemIds;

  /// What the bar offers, left to right.
  final List<SelectionAction> actions;

  /// The shelf itself — normally a `JustifiedWallpaperGrid`.
  final Widget child;

  /// Whether the bar takes its height *from* [child] or adds to it.
  ///
  /// True for a grid that fills its viewport: the bar appears and the wall
  /// shortens. False for a shelf that is already a fixed height and sits in an
  /// unbounded column — the Library hub's downloads strip — where an `Expanded`
  /// has no flex to take and would throw. There the bar simply stacks above.
  final bool expandChild;

  /// The layout is the **same shape whether or not the shelf is selecting**,
  /// and that is a bug fix, not a tidiness preference.
  ///
  /// This used to return [child] bare while idle and wrap it in a [Column] on
  /// the way into the mode. Those are different widgets at the same slot, so
  /// Flutter could not update the element — it tore the whole shelf down and
  /// inflated a new one, and the scroll position went with it. Starting a
  /// multi-select threw the wall back to the top, so picking the *second*
  /// wallpaper meant scrolling all the way down again (owner, on device).
  /// Cancelling did it a second time, right after the batch ran.
  ///
  /// So the [Column] is always here and the bar's slot is filled by a
  /// zero-height box while idle: only the first child changes type, and the
  /// shelf below it keeps its element, its [ScrollPosition] and its decoded
  /// images. Guarded by `selection_shelf_test.dart`.
  @override
  Widget build(BuildContext context) {
    final WallpaperSelection? selection = WallpaperSelectionScope.of(context);
    // No scope above us is a mount-time fact, not a mode: a shelf that can
    // never select keeps the bare child and never takes the Column's bounded
    // height requirement.
    if (selection == null) return child;
    return Column(
      mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        if (selection.isActive)
          _SelectionBar(
            selection: selection,
            itemIds: itemIds,
            actions: actions,
          )
        else
          const SizedBox.shrink(),
        if (expandChild) Expanded(child: child) else child,
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selection,
    required this.itemIds,
    required this.actions,
  });

  final WallpaperSelection selection;
  final List<String> itemIds;
  final List<SelectionAction> actions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.batchCancel,
              onPressed: selection.clear,
            ),
            Expanded(child: Text(l10n.batchSelectedCount(selection.count))),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: l10n.batchSelectAll,
              onPressed: () => selection.addAll(itemIds),
            ),
            for (final SelectionAction action in actions) _button(action),
          ],
        ),
      ),
    );
  }

  /// Disabled at zero ticks rather than hidden.
  ///
  /// An explicit mode can sit at nothing selected — that is the trade the
  /// *Select* button bought — so the bar has to say what it would do without
  /// pretending it can do it yet. Hiding the actions would make the bar change
  /// shape on every first and last tick.
  Widget _button(SelectionAction action) {
    return IconButton(
      icon: Icon(action.icon),
      tooltip: action.label,
      onPressed: selection.count == 0 ? null : () => unawaited(_run(action)),
    );
  }

  /// Resolves ids against the shelf's current list rather than acting on
  /// whatever the selection remembers, then leaves the mode if it ran.
  Future<void> _run(SelectionAction action) async {
    final List<String> selected = itemIds.where(selection.contains).toList();
    if (await action.run(selected)) selection.clear();
  }
}
