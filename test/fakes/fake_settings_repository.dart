import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// In-memory [SettingsRepository] holding one set of settings.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a fake that starts at [settings], or the domain defaults.
  FakeSettingsRepository({StorageSettings? settings})
    : _settings = settings ?? StorageSettings.defaults;

  StorageSettings _settings;

  /// The settings a save last wrote, readable by assertions.
  StorageSettings get saved => _settings;

  @override
  Future<StorageSettings> loadStorageSettings() async => _settings;

  @override
  Future<void> saveStorageSettings(StorageSettings settings) async {
    _settings = settings;
  }
}
