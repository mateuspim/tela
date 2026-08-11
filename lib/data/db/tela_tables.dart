/// Every table tela keeps, and the columns two of them share.
///
/// Apart from the database that opens them: the shapes here change rarely and
/// each change is a migration, while the statements over them change with every
/// feature. Drift generates both into `tela_database.g.dart` all the same —
/// tables carry no part file of their own, only the `@DriftDatabase` that lists
/// them does.
library;

import 'package:drift/drift.dart';

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

/// The columns that spell out one whole wallpaper, shared by the tables that
/// keep one.
///
/// Both favorites and downloads store the wallpaper *whole* rather than as a
/// bare id, for the same reason: their grids must render with no network at
/// all, and an applied or re-applied wallpaper needs every field an id alone
/// would have to re-fetch. Sharing the columns keeps the two tables from
/// drifting apart field by field.
mixin WallpaperColumns on Table {
  /// `SourceId` value of the site it came from, e.g. `"wallhaven"`.
  ///
  /// Half the primary key, and the reason there is one: an id is unique to its
  /// source, so two sources can issue the same one — Konachan #12345 and
  /// yande.re #12345 are two wallpapers, and a table keyed on the number alone
  /// would let the second silently overwrite the first.
  TextColumn get source => text()();

  /// The id that source issued, e.g. `"e7jvjd"`.
  TextColumn get id => text()();

  /// The wallpaper's public page on its own site.
  ///
  /// Stored rather than composed on read for the same reason the model stopped
  /// composing it: only the source's adapter knows its URL shape, and a stored
  /// row must render offline without one.
  TextColumn get pageUrl => text()();

  /// Full-resolution source — what apply and download stream from.
  TextColumn get fullImageUrl => text()();

  /// The three Wallhaven thumbnail sizes, kept as-is.
  TextColumn get thumbSmallUrl => text()();

  /// Preview-sized thumbnail.
  TextColumn get thumbLargeUrl => text()();

  /// Ratio-preserving thumbnail — the one the masonry grid draws.
  TextColumn get thumbOriginalUrl => text()();

  /// Pixel width of [fullImageUrl].
  IntColumn get width => integer()();

  /// Pixel height of [fullImageUrl].
  IntColumn get height => integer()();

  /// Size of [fullImageUrl] in bytes.
  IntColumn get fileSizeBytes => integer()();

  /// Purity enum name. Routes storage, so its read has a fail-safe parse.
  TextColumn get purity => text()();

  /// Category enum name, or empty for a source that has no such axis.
  TextColumn get category => text()();

  /// Dominant colours, comma-joined in Wallhaven's order.
  TextColumn get colors => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{source, id};
}

/// One favorited wallpaper, stored whole rather than as a bare id.
///
/// Every field the grid and the apply action need lives here, so the favorites
/// screen renders — and a saved wallpaper can still be applied — with no
/// network at all. An id-only table would make favorites unreadable offline,
/// which is the one thing they exist to survive.
@DataClassName('FavoriteRow')
class FavoriteWallpapers extends Table with WallpaperColumns {
  /// When it was favorited. Orders the grid, newest first.
  DateTimeColumn get savedAt => dateTime()();
}

/// One wallpaper this device downloaded, and where the file landed.
///
/// Keyed by source and id, so downloading the same wallpaper twice updates one
/// row rather than stacking duplicates in the history.
///
/// **Never holds an explicit wallpaper, and never an app-private one.** Both
/// live in the private library, behind `FLAG_SECURE` and the app-lock; a row
/// here would be an ungated index of them, in a database Android's Auto Backup
/// carries off the device. The tier rule is the one that is easy to miss: a
/// perfectly safe wallpaper sent to the `appPrivate` tier was sent there to be
/// private, and purity has nothing to say about that.
@DataClassName('DownloadRow')
class DownloadedWallpapers extends Table with WallpaperColumns {
  /// `StorageTier` name of the destination it actually landed in.
  TextColumn get tier => text()();

  /// The file's URI: MediaStore content, a SAF document, or a local file.
  TextColumn get location => text()();

  /// When it was downloaded. Orders the history, newest first.
  DateTimeColumn get downloadedAt => dateTime()();
}

/// One wallpaper this device still owes a download for.
///
/// Keyed by source and id like the two tables above, which is what makes
/// enqueuing idempotent: ticking the same shelf twice updates nothing rather
/// than lining the same wallpaper up to be downloaded twice.
///
/// **Unlike [DownloadedWallpapers], this table does hold explicit and
/// app-private entries**, and the difference is deliberate — see
/// `DownloadQueue`'s docstring. A download row is a permanent index; a queue
/// row is a work item that is deleted the moment the file lands. Refusing to
/// hold one would not protect anything, it would silently decline to download
/// a wallpaper the user asked for. What still applies is the screen rule: the
/// queue UI does not render an explicit entry identifiably.
@DataClassName('QueueRow')
class DownloadQueueEntries extends Table with WallpaperColumns {
  /// `StorageTier` name of the per-download override, or null to resolve the
  /// destination when the entry actually runs.
  ///
  /// Nullable because null is the ordinary case, not a missing value: a
  /// pin-governed batch enqueues null on purpose so each download follows the
  /// pin and the purity's configured tier at the moment it runs.
  TextColumn get tier => text().nullable()();

  /// `DownloadQueueState` name: pending, running or failed.
  TextColumn get state => text()();

  /// How many times this entry has been tried.
  IntColumn get attempts => integer().withDefault(const Constant<int>(0))();

  /// `ImageStoreProblem` name of the last failure, or null if it has not
  /// failed. Never a URL or a path — the same rule `ImageStoreFailure` follows.
  TextColumn get failure => text().nullable()();

  /// When it was queued. Orders the queue, oldest first — a queue is a line.
  DateTimeColumn get queuedAt => dateTime()();
}

/// One tag the user never wants to see again, kept by id so a rename upstream
/// cannot slip a blocked tag back into a listing.
@DataClassName('BlockedTagRow')
class BlockedTags extends Table {
  /// Wallhaven's numeric tag id — what the `-id:{n}` operator actually
  /// excludes.
  IntColumn get id => integer()();

  /// Display name, kept only so the management screen can show what was
  /// blocked without a network call.
  TextColumn get name => text()();

  /// When it was blocked. Orders the management screen, newest first.
  DateTimeColumn get blockedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
