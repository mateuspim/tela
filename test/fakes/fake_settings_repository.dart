import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// In-memory [SettingsRepository] holding one set of settings.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a fake that starts at [settings], or the domain defaults.
  FakeSettingsRepository({
    StorageSettings? settings,
    bool privateLibraryLocked = false,
    bool nsfwOnRemovableAcknowledged = false,
    AccountSettings? accountDefaults,
    BrowseDefaultsSource source = BrowseDefaultsSource.account,
    BrowseDefaults? deviceDefaults,
    AccentColor? accent,
    TileDensity density = TileDensity.medium,
    Map<Purity, DownloadDestinationStreak>? streaks,
    StorageTier? pinnedDownloadTier,
  }) : _streaks = <Purity, DownloadDestinationStreak>{...?streaks},
       _pinnedDownloadTier = pinnedDownloadTier,
       _settings = settings ?? StorageSettings.defaults,
       _privateLibraryLocked = privateLibraryLocked,
       _nsfwOnRemovableAcknowledged = nsfwOnRemovableAcknowledged,
       _accountDefaults = accountDefaults,
       _source = source,
       _deviceDefaults = deviceDefaults,
       _accent = accent,
       _density = density;

  StorageSettings _settings;
  bool _privateLibraryLocked;
  bool _nsfwOnRemovableAcknowledged;
  AccountSettings? _accountDefaults;
  BrowseDefaultsSource _source;
  BrowseDefaults? _deviceDefaults;
  AccentColor? _accent;
  TileDensity _density;
  StorageTier? _pinnedDownloadTier;

  /// Streaks by storage bucket, seeded through the constructor and keyed the
  /// same way the Drift adapter keys its two rows.
  final Map<Purity, DownloadDestinationStreak> _streaks;

  /// The streak currently recorded for [purity]'s bucket, if any.
  DownloadDestinationStreak? streakSaved(Purity purity) =>
      _streaks[StorageSettings.bucketFor(purity)];

  /// The settings a save last wrote, readable by assertions.
  StorageSettings get saved => _settings;

  /// Whether the private library's lock is currently on.
  bool get lockSaved => _privateLibraryLocked;

  /// Whether the NSFW-on-removable warning has been acknowledged.
  bool get nsfwOnRemovableAckSaved => _nsfwOnRemovableAcknowledged;

  /// The account defaults currently stored, if any.
  AccountSettings? get accountSaved => _accountDefaults;

  /// The source browse currently takes its defaults from.
  BrowseDefaultsSource get sourceSaved => _source;

  /// The device snapshot currently stored, if any.
  BrowseDefaults? get deviceSaved => _deviceDefaults;

  /// The accent currently stored, or null when following the device palette.
  AccentColor? get accentSaved => _accent;

  /// The "Keep sending here" pin currently stored, or null when none is set.
  StorageTier? get pinnedTierSaved => _pinnedDownloadTier;

  @override
  Future<StorageSettings> loadStorageSettings() async => _settings;

  @override
  Future<void> saveStorageSettings(StorageSettings settings) async {
    _settings = settings;
  }

  @override
  Future<bool> loadNsfwOnRemovableAcknowledged() async =>
      _nsfwOnRemovableAcknowledged;

  @override
  Future<void> saveNsfwOnRemovableAcknowledged({
    required bool acknowledged,
  }) async {
    _nsfwOnRemovableAcknowledged = acknowledged;
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

  @override
  Future<BrowseDefaultsSource> loadBrowseDefaultsSource() async => _source;

  @override
  Future<void> setBrowseDefaultsSource(BrowseDefaultsSource source) async {
    _source = source;
  }

  @override
  Future<BrowseDefaults?> loadDeviceDefaults() async => _deviceDefaults;

  @override
  Future<void> saveDeviceDefaults(BrowseDefaults defaults) async {
    _deviceDefaults = defaults;
  }

  @override
  Future<AccentColor?> loadAccentColor() async => _accent;

  @override
  Future<void> saveAccentColor(AccentColor accent) async {
    _accent = accent;
  }

  @override
  Future<void> clearAccentColor() async {
    _accent = null;
  }

  @override
  Future<TileDensity> loadTileDensity() async => _density;

  @override
  Future<void> saveTileDensity(TileDensity density) async {
    _density = density;
  }

  @override
  Future<DownloadDestinationStreak?> loadDestinationStreak(
    Purity purity,
  ) async => _streaks[StorageSettings.bucketFor(purity)];

  @override
  Future<void> recordDestination(Purity purity, StorageTier tier) async {
    final Purity bucket = StorageSettings.bucketFor(purity);
    // Through the domain's own arithmetic, not a reimplementation of it: a fake
    // that counted differently from Drift would let a test prove nothing.
    _streaks[bucket] = DownloadDestinationStreak.extending(
      _streaks[bucket],
      tier,
    );
  }

  @override
  Future<StorageTier?> loadPinnedDownloadTier() async => _pinnedDownloadTier;

  @override
  Future<void> setPinnedDownloadTier(StorageTier? tier) async {
    _pinnedDownloadTier = tier;
  }
}
