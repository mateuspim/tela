import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// In-memory [SettingsRepository] holding one set of settings.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a fake that starts at [settings], or the domain defaults.
  FakeSettingsRepository({
    StorageSettings? settings,
    bool privateLibraryLocked = false,
    AccountSettings? accountDefaults,
  }) : _settings = settings ?? StorageSettings.defaults,
       _privateLibraryLocked = privateLibraryLocked,
       _accountDefaults = accountDefaults;

  StorageSettings _settings;
  bool _privateLibraryLocked;
  AccountSettings? _accountDefaults;

  /// The settings a save last wrote, readable by assertions.
  StorageSettings get saved => _settings;

  /// Whether the private library's lock is currently on.
  bool get lockSaved => _privateLibraryLocked;

  /// The account defaults currently stored, if any.
  AccountSettings? get accountSaved => _accountDefaults;

  @override
  Future<StorageSettings> loadStorageSettings() async => _settings;

  @override
  Future<void> saveStorageSettings(StorageSettings settings) async {
    _settings = settings;
  }

  @override
  Future<bool> isPrivateLibraryLocked() async => _privateLibraryLocked;

  @override
  Future<void> setPrivateLibraryLocked({required bool locked}) async {
    _privateLibraryLocked = locked;
  }

  @override
  Future<AccountSettings?> loadAccountDefaults() async => _accountDefaults;

  @override
  Future<void> saveAccountDefaults(AccountSettings account) async {
    _accountDefaults = account;
  }

  @override
  Future<void> forgetAccountDefaults() async {
    _accountDefaults = null;
  }
}
