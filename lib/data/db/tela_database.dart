import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'tela_database.g.dart';

/// One persisted preference, addressed by a stable string key.
///
/// A key/value shape rather than a column per setting: settings arrive one
/// slice at a time, and a new one should be a new row, not a migration.
@DataClassName('SettingEntry')
class SettingEntries extends Table {
  /// The setting's stable identifier, e.g. `storage.tier.nsfw`.
  TextColumn get key => text()();

  /// The stored value, serialised by the adapter that owns the key.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// tela's local database: the one SQLite connection the app opens.
///
/// Adapters in `data/` own the meaning of what they store; features never see
/// this class, only the domain ports its adapters implement.
///
/// ```dart
/// final TelaDatabase db = TelaDatabase.open();
/// ```
@DriftDatabase(tables: <Type>[SettingEntries])
class TelaDatabase extends _$TelaDatabase {
  /// Wraps an existing connection — the seam tests use for an in-memory one.
  TelaDatabase(super.e);

  /// Opens the on-device database file.
  factory TelaDatabase.open() {
    return TelaDatabase(driftDatabase(name: 'tela'));
  }

  @override
  int get schemaVersion => 1;

  /// Reads one setting, or null when it was never written.
  Future<String?> settingValue(String key) {
    final SimpleSelectStatement<$SettingEntriesTable, SettingEntry> query =
        select(settingEntries)
          ..where(($SettingEntriesTable row) => row.key.equals(key));
    return query.map((SettingEntry row) => row.value).getSingleOrNull();
  }

  /// Writes one setting, replacing any previous value for [key].
  Future<void> putSetting(String key, String value) {
    return into(settingEntries).insertOnConflictUpdate(
      SettingEntriesCompanion.insert(key: key, value: value),
    );
  }
}
