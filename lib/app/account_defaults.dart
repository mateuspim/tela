import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/account_settings.dart';

/// The Wallhaven account's browse defaults, as this device last synced them.
///
/// Null until a key is saved, and null again once one is forgotten.
final AsyncNotifierProvider<AccountDefaultsController, AccountSettings?>
accountDefaultsProvider =
    AsyncNotifierProvider<AccountDefaultsController, AccountSettings?>(
      AccountDefaultsController.new,
    );

/// Holds the synced account defaults for whoever needs them.
///
/// App-level rather than a feature's, because two features meet here and
/// features may not import each other (CLAUDE.md): **settings** changes this —
/// saving a key syncs the defaults, forgetting one drops them — and **browse**
/// reads it, adopting the defaults into its query. Neither knows about the
/// other; both know about this.
///
/// It re-reads through `LoadAccountDefaults` rather than caching what a sync
/// returned, so the explicit-content guard in that use case sits on the only
/// path the defaults can reach the UI by.
///
/// ```dart
/// ref.invalidate(accountDefaultsProvider); // after the key changed
/// ```
class AccountDefaultsController extends AsyncNotifier<AccountSettings?> {
  @override
  Future<AccountSettings?> build() => ref.watch(loadAccountDefaultsProvider)();
}
