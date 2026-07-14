import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// In-memory [SettingsRepository] holding one set of settings.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a fake that starts at [settings], or the domain defaults.
  FakeSettingsRepository({
    StorageSettings? settings,
    bool privateLibraryLocked = false,
  }) : _settings = settings ?? StorageSettings.defaults,
       _privateLibraryLocked = privateLibraryLocked;

  StorageSettings _settings;
  bool _privateLibraryLocked;

  /// The settings a save last wrote, readable by assertions.
  StorageSettings get saved => _settings;

  /// Whether the private library's lock is currently on.
  bool get lockSaved => _privateLibraryLocked;

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
}
