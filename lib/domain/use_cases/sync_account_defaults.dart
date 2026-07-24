import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/source_failure.dart';
import 'package:tela/domain/ports/settings_repository.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

/// Pulls the Wallhaven account's browse defaults and keeps them.
///
/// Runs exactly once per saved key, from inside `SaveApiKey` — the one request
/// both proves the key and returns the defaults, so syncing costs nothing on
/// top of a save. There is no periodic refresh: an account's defaults change
/// about as often as its password, and a poll would spend the 45 req/min budget
/// on a question nobody asked.
///
/// ```dart
/// final AccountSettings account = await syncAccountDefaults();
/// ```
class SyncAccountDefaults {
  /// Creates the use case over Wallhaven and the local settings store.
  const SyncAccountDefaults({
    required WallpaperSource source,
    required SettingsRepository settings,
  }) : _source = source,
       _settings = settings;

  final WallpaperSource _source;
  final SettingsRepository _settings;

  /// Fetches the defaults and persists them, returning what it stored.
  ///
  /// Throws [InvalidApiKeyFailure] when the stored key is missing or rejected,
  /// and nothing is written — a key Wallhaven will not answer for has no
  /// defaults to adopt.
  Future<AccountSettings> call() async {
    final AccountSettings account = await _source.accountSettings();
    await _settings.saveAccountDefaults(account);
    return account;
  }
}
