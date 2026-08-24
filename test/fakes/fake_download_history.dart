import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/tag_folder.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';

/// In-memory [DownloadHistory], newest download first.
///
/// Records whatever it is handed, explicit wallpapers included, so a test can
/// prove that keeping those out is the *caller's* rule and not an accident of
/// the store. The Drift adapter has its own test for its own refusal.
class FakeDownloadHistory implements DownloadHistory {
  /// Creates a fake holding [initial], oldest first.
  FakeDownloadHistory({List<DownloadRecord> initial = const <DownloadRecord>[]})
    : _recorded = List<DownloadRecord>.of(initial);

  final List<DownloadRecord> _recorded;

  /// Every recorded download, oldest first — the order they arrived in.
  List<DownloadRecord> get recorded => List<DownloadRecord>.unmodifiable(
    _recorded,
  );

  /// How many times the history has been listed.
  ///
  /// The download queue re-reads this after every entry it settles, and a
  /// hundred-wallpaper batch settles three a second — so "how often" is a
  /// behaviour worth pinning, not an implementation detail. See
  /// `DownloadQueueController.listingRefreshWindow`.
  int reads = 0;

  @override
  Future<List<DownloadRecord>> downloads() async {
    reads++;
    return _recorded.reversed.toList();
  }

  @override
  Future<void> forget(WallpaperRef ref) async {
    _recorded.removeWhere((DownloadRecord d) => d.wallpaper.ref == ref);
  }

  /// Batch sizes [forgetAll] was called with, in call order — so a test can
  /// prove a bulk cleanup made one call rather than one per row.
  final List<int> forgetAllBatchSizes = <int>[];

  @override
  Future<void> forgetAll(Iterable<WallpaperRef> refs) async {
    final Set<WallpaperRef> targets = Set<WallpaperRef>.of(refs);
    forgetAllBatchSizes.add(targets.length);
    _recorded.removeWhere(
      (DownloadRecord d) => targets.contains(d.wallpaper.ref),
    );
  }

  @override
  Future<void> record({
    required Wallpaper wallpaper,
    required StorageTier tier,
    required Uri location,
    TagFolder? tag,
  }) async {
    _recorded
      ..removeWhere((DownloadRecord d) => d.wallpaper.id == wallpaper.id)
      ..add(
        DownloadRecord(
          wallpaper: wallpaper,
          tier: tier,
          location: location,
          downloadedAt: DateTime(2026, 7, 14),
          tag: tag,
        ),
      );
  }

  /// Re-points a row at a moved file, replacing location and tag together — a
  /// fake that let them diverge could not catch a caller that writes one
  /// without the other.
  @override
  Future<void> retag({
    required WallpaperRef ref,
    required Uri location,
    required TagFolder? tag,
  }) async {
    final int at = _recorded.indexWhere(
      (DownloadRecord d) => d.wallpaper.ref == ref,
    );
    if (at < 0) return;
    final DownloadRecord old = _recorded[at];
    _recorded[at] = DownloadRecord(
      wallpaper: old.wallpaper,
      tier: old.tier,
      location: location,
      downloadedAt: old.downloadedAt,
      tag: tag,
    );
  }
}
