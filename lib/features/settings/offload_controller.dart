import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/offload_group.dart';

/// What is on built-in storage right now and could move to a card.
///
/// autoDispose and re-surveyed on each visit, for the reason
/// `cachedImageBytesProvider` is: the figures are only true for as long as
/// nobody downloads, and a stale "3.2 GB" over a library that has since doubled
/// is worse than a moment's spinner.
final FutureProvider<List<OffloadGroup>> offloadGroupsProvider =
    FutureProvider.autoDispose<List<OffloadGroup>>((Ref ref) {
      return ref.read(surveyOffloadGroupsProvider)();
    });

/// Which groups the user has ticked.
///
/// autoDispose, so leaving the screen clears the ticks: the survey behind them
/// is re-read on the next visit, and a tick kept against a group that has since
/// changed size would be a promise about files nobody counted.
final NotifierProvider<OffloadSelection, Set<OffloadKind>>
offloadSelectionProvider = NotifierProvider<OffloadSelection, Set<OffloadKind>>(
  OffloadSelection.new,
  isAutoDispose: true,
);

/// The ticks on the offload screen, and nothing else.
///
/// Starts empty rather than pre-ticked. Two of the three groups change more
/// than a file's location — the gallery one leaves Photos, the private one
/// leaves the app-lock — so a screen that arrives with everything selected is
/// one mis-tap away from a decision the user never made.
class OffloadSelection extends Notifier<Set<OffloadKind>> {
  /// Nothing ticked. See the class docstring for why it is not everything.
  @override
  Set<OffloadKind> build() => const <OffloadKind>{};

  /// Ticks or unticks [kind].
  void toggle(OffloadKind kind) {
    final Set<OffloadKind> next = Set<OffloadKind>.of(state);
    if (!next.remove(kind)) next.add(kind);
    state = next;
  }
}
