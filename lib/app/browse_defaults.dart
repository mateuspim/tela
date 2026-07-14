import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/account_defaults.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// The filters browse opens on, and where the user chose to take them from.
final AsyncNotifierProvider<BrowseDefaultsController, ActiveBrowseDefaults>
browseDefaultsProvider =
    AsyncNotifierProvider<BrowseDefaultsController, ActiveBrowseDefaults>(
      BrowseDefaultsController.new,
    );

/// The snapshot saved on this device, or null when none ever was.
///
/// Separate from [browseDefaultsProvider], which answers what is *in force*.
/// Settings has to describe each source on its own terms — a row summarising
/// whichever source happens to be active would have the account's line echo the
/// device's filters back at you, which is worse than no summary: it is the line
/// you read *before* switching.
final FutureProvider<BrowseDefaults?> deviceDefaultsProvider =
    FutureProvider<BrowseDefaults?>((Ref ref) {
      // Rebuilds with the choice, so saving a snapshot updates its own summary.
      ref.watch(browseDefaultsProvider);
      return ref.watch(settingsRepositoryProvider).loadDeviceDefaults();
    });

/// Owns the browse-defaults choice for whoever needs it.
///
/// App-level rather than a feature's, for the reason
/// `AccountDefaultsController` already is: two features meet here and features
/// may not import each other (CLAUDE.md). **Settings** writes it — the source
/// toggle, and the refresh that re-pulls the account — and **browse** reads it,
/// opening its listing on whatever it says. The filter sheet writes it too,
/// when it saves the filters you are looking at as the device's snapshot.
///
/// It re-resolves through `ResolveBrowseDefaults` on every change rather than
/// caching what a write returned, so the "no purity, ever" rule sits on the
/// one path the defaults can reach the UI by.
///
/// ```dart
/// final BrowseDefaultsController defaults =
///     ref.read(browseDefaultsProvider.notifier);
/// await defaults.useSource(BrowseDefaultsSource.device);
/// ```
class BrowseDefaultsController extends AsyncNotifier<ActiveBrowseDefaults> {
  @override
  Future<ActiveBrowseDefaults> build() async {
    // Wait on the account load rather than merely depending on it: it is what
    // performs the backfill for a key that predates the sync, and resolving
    // before it has written its rows would answer with defaults that are about
    // to change. Saving a key syncs, forgetting one drops — either way this
    // re-runs, because the account's defaults are what moved.
    await ref.watch(accountDefaultsProvider.future);
    return ref.watch(resolveBrowseDefaultsProvider)();
  }

  /// Switches which source browse opens on, and re-resolves.
  Future<void> useSource(BrowseDefaultsSource source) async {
    await ref.read(settingsRepositoryProvider).setBrowseDefaultsSource(source);
    ref.invalidateSelf();
  }

  /// Saves the filters [query] currently expresses as this device's snapshot,
  /// and browses on them.
  ///
  /// Switching the source is not a separate step the user has to remember:
  /// "save these as my default" that left the app still opening on the
  /// account's would be a button that appears to do nothing.
  Future<void> saveDeviceDefaults(SearchQuery query) async {
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.saveDeviceDefaults(BrowseDefaults.of(query));
    await settings.setBrowseDefaultsSource(BrowseDefaultsSource.device);
    ref.invalidateSelf();
  }

  /// Re-pulls the Wallhaven account's settings, for when they changed on the
  /// web.
  ///
  /// On demand only. There is still no periodic refresh: an account's defaults
  /// change about as often as its password, and a poll would spend the
  /// 45 req/min budget on a question nobody asked. Throws a `WallhavenFailure`
  /// on a key that is rejected or an account tela cannot reach — the caller
  /// shows it.
  Future<void> refreshFromAccount() async {
    await ref.read(syncAccountDefaultsProvider)();
    ref.invalidate(accountDefaultsProvider);
  }
}
