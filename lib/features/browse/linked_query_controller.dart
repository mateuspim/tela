import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps the family provider types out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/features/browse/browse_filter_scope.dart';
import 'package:tela/features/browse/browse_query_controller.dart';

/// The filters one linked listing is browsing under, keyed by its identity.
///
/// Keyed rather than global so two listings reached one after the other do not
/// inherit each other's narrowing. **autoDispose**, so leaving a listing lets
/// its filters go rather than accumulating one query per tag ever followed —
/// and so coming back to a tag arrives fresh from Browse, the same way arriving
/// the first time did.
final NotifierProviderFamily<LinkedQueryController, SearchQuery, String>
linkedQueryProvider = NotifierProvider.autoDispose
    .family<LinkedQueryController, SearchQuery, String>(
      LinkedQueryController.new,
    );

/// A tag or uploader listing's own filters: inherited on arrival, then its own.
///
/// **Seeded from Browse, and that is deliberate.** Following a tag out of a
/// listing you have already narrowed should land you in that same world — the
/// screen's own promise, "their filters still apply here, as they do on
/// wallhaven.cc". What changes is only what happens next: an edit made *here*
/// stays here, because a pushed listing is a detour and Back should leave the
/// Browse tabs exactly as they were.
///
/// ```dart
/// ref.watch(linkedQueryProvider('linked:tag:37'));
/// ```
class LinkedQueryController extends Notifier<SearchQuery>
    implements BrowseFilterScope {
  /// Creates the controller for the listing [identity] names.
  LinkedQueryController(this.identity);

  /// The shelf this belongs to, e.g. `linked:tag:37` — the same identity its
  /// gallery session uses, so one listing's filters can never be another's.
  final String identity;

  @override
  SearchQuery build() {
    // read, not watch: inheriting is a starting point, not a subscription. A
    // later change to Browse's own filters must not reach in and re-narrow a
    // listing the user has since filtered by hand.
    return ref.read(browseQueryProvider);
  }

  @override
  SearchQuery get filters => state;

  @override
  void applyFilters(SearchQuery filters) {
    state = filters;
  }

  /// Resets to the same defaults Browse resets to — **including purity back to
  /// safe**. Re-inheriting Browse's *current* query here would be the obvious
  /// shortcut and the wrong one: it would leave a sketchy session sketchy, and
  /// this is the button whose whole job is ending one.
  @override
  void clearFilters() {
    state = ref.read(browseQueryProvider.notifier).defaultQuery;
  }
}
