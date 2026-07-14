import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/use_cases/load_account_defaults.dart';

/// Works out the filters browse opens on: the account's, this device's, or
/// tela's own when the chosen source has nothing to say.
///
/// The fallback is never an error. A source with no stored defaults — an
/// account that has not synced yet, a device whose snapshot was never saved —
/// simply yields `const BrowseDefaults()`, which is somewhere the app is always
/// happy to browse. Picking a source is a preference, not a promise that it has
/// an answer.
///
/// ```dart
/// final BrowseDefaults defaults = await resolveBrowseDefaults();
/// ```
class ResolveBrowseDefaults {
  /// Creates the use case over the settings store and the account load (which
  /// carries the backfill for a key that predates the sync).
  const ResolveBrowseDefaults({
    required SettingsRepository settings,
    required LoadAccountDefaults loadAccount,
  }) : _settings = settings,
       _loadAccount = loadAccount;

  final SettingsRepository _settings;
  final LoadAccountDefaults _loadAccount;

  /// The effective defaults, and the source they came from. Never throws: an
  /// account tela cannot reach costs the defaults, not the browse screen.
  Future<ActiveBrowseDefaults> call() async {
    final BrowseDefaultsSource source = await _settings
        .loadBrowseDefaultsSource();
    final BrowseDefaults defaults = switch (source) {
      BrowseDefaultsSource.account => await _fromAccount(),
      BrowseDefaultsSource.device => await _fromDevice(),
    };
    return ActiveBrowseDefaults(source: source, defaults: defaults);
  }

  Future<BrowseDefaults> _fromAccount() async {
    final AccountSettings? account = await _loadAccount();
    return account?.toBrowseDefaults() ?? const BrowseDefaults();
  }

  Future<BrowseDefaults> _fromDevice() async {
    return await _settings.loadDeviceDefaults() ?? const BrowseDefaults();
  }
}
