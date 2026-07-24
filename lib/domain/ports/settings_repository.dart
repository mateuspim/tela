import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_settings.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tile_density.dart';

/// Reads and writes the user's persisted preferences.
///
/// A pure-domain port: no package sits behind it, and the fact that its adapter
/// speaks SQL is not something a feature or a use case may observe.
abstract interface class SettingsRepository {
  /// The current storage routing, or [StorageSettings.defaults] when unset.
  ///
  /// Never throws: unreadable or corrupt storage falls back to the defaults,
  /// because a download must still have somewhere safe to go.
  Future<StorageSettings> loadStorageSettings();

  /// Persists [settings] as the new storage routing.
  Future<void> saveStorageSettings(StorageSettings settings);

  /// Whether the user has accepted that explicit downloads on a removable card
  /// give up the private tier's protections — pull the card and read it
  /// anywhere, no app-lock, no `FLAG_SECURE`.
  ///
  /// A one-time confirmation: never asked answers `false`, so the warning still
  /// fires. A row that was written but cannot be *read* answers `false` too —
  /// the safe reading of a *warning* is to show it, not to suppress it, the
  /// opposite of the private-lock's fail-closed. Never throws.
  Future<bool> loadNsfwOnRemovableAcknowledged();

  /// Records whether the user accepted explicit downloads on a removable card.
  Future<void> saveNsfwOnRemovableAcknowledged({required bool acknowledged});

  /// Whether the private library asks for a biometric or PIN before it opens.
  ///
  /// The lock is opt-in, so a setting that was never written answers `false`. A
  /// setting that was written but cannot be *read* answers `true`: "I can't
  /// tell whether this was locked" has only one safe reading. Never throws.
  Future<bool> isPrivateLibraryLocked();

  /// Turns the private library's lock on or off.
  Future<void> setPrivateLibraryLocked({required bool locked});

  /// The Wallhaven account's browse defaults as this device last synced them,
  /// or null when no key has ever been saved.
  ///
  /// Never throws: a row it cannot read answers null, and null simply means
  /// tela browses on its own defaults.
  Future<AccountSettings?> loadAccountDefaults();

  /// Persists [account] as the defaults a fresh listing starts from.
  Future<void> saveAccountDefaults(AccountSettings account);

  /// Drops the synced defaults, which is what forgetting the API key does.
  ///
  /// They belong to an account this device can no longer reach: an explicit
  /// purity outlives its key by exactly one 401 otherwise.
  Future<void> forgetAccountDefaults();

  /// Where browse takes its opening filters from.
  ///
  /// Answers [BrowseDefaultsSource.account] when never set, which is what every
  /// build before the switch did — an upgrade must not silently move somebody's
  /// front page. Never throws: an unreadable row answers the same.
  Future<BrowseDefaultsSource> loadBrowseDefaultsSource();

  /// Persists which source browse opens on.
  Future<void> setBrowseDefaultsSource(BrowseDefaultsSource source);

  /// The filters saved from this device's filter sheet, or null when none have
  /// been saved — in which case tela's own defaults stand in.
  ///
  /// Never throws: a snapshot it cannot read answers null.
  Future<BrowseDefaults?> loadDeviceDefaults();

  /// Persists [defaults] as the snapshot the device browses on.
  Future<void> saveDeviceDefaults(BrowseDefaults defaults);

  /// The brand accent the user chose, or null to follow the device palette
  /// (Material You), which is what tela ships on.
  ///
  /// Never throws: a row it cannot parse answers null, and null is already the
  /// safe reading — an unreadable accent falls back to the device's own.
  Future<AccentColor?> loadAccentColor();

  /// Persists [accent] as the brand colour used for tela's own moments.
  Future<void> saveAccentColor(AccentColor accent);

  /// Drops the chosen accent, which is what "follow wallpaper" does.
  ///
  /// The absence of the row *is* follow-system, so this deletes rather than
  /// writes a sentinel — see the device-colour filter for the same rule.
  Future<void> clearAccentColor();

  /// How large the wallpaper shelves draw their tiles, or
  /// [TileDensity.medium] when unset — the density every build before this
  /// setting drew, so an upgrade does not resize somebody's wall.
  ///
  /// Never throws: an unreadable row answers the same default. Unlike the
  /// accent there is no absent-means-follow-system state, so this returns a
  /// value rather than a nullable one.
  Future<TileDensity> loadTileDensity();

  /// Persists [density] as the size the shelves draw at.
  Future<void> saveTileDensity(TileDensity density);

  /// How many downloads in a row have landed in the same tier for [purity], or
  /// null when there is no run to speak of yet.
  ///
  /// Keyed by [StorageSettings.bucketFor], so `sketchy` shares `sfw`'s streak
  /// exactly as it shares its configured tier.
  ///
  /// Never throws: a row it cannot read answers null, which simply means
  /// nothing is suggested. A memory is a convenience, and losing one may never
  /// cost a download.
  Future<DownloadDestinationStreak?> loadDestinationStreak(Purity purity);

  /// Records that a [purity] download landed in [tier], growing the streak when
  /// it matches the last one and starting a fresh one when it does not.
  ///
  /// Called for **every** download, not only overridden ones: a streak that
  /// merely agrees with the configured tier is what tells the caller it has
  /// nothing to suggest.
  Future<void> recordDestination(Purity purity, StorageTier tier);

  /// The "Keep sending here" pin — one tier every download goes to until the
  /// user changes it — or null when no pin is set (route by the per-purity
  /// configured tier as usual).
  ///
  /// Purity-flat on purpose: the pin is one destination for all purities. The
  /// NSFW invariant is applied at routing ([StorageSettings.tierWithPin]), not
  /// here, so a `sharedGallery` pin is stored plainly and simply does not
  /// govern explicit downloads.
  ///
  /// Never throws: an unreadable row answers null, the safe reading — no pin
  /// falls back to the configured routing rather than force a destination.
  Future<StorageTier?> loadPinnedDownloadTier();

  /// Pins [tier] as the destination every download goes to until changed, or
  /// clears the pin when [tier] is null.
  Future<void> setPinnedDownloadTier(StorageTier? tier);
}
