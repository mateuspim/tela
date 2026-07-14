import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper.dart';
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

  @override
  Future<List<DownloadRecord>> downloads() async => _recorded.reversed.toList();

  @override
  Future<void> record({
    required Wallpaper wallpaper,
    required StorageTier tier,
    required Uri location,
  }) async {
    _recorded
      ..removeWhere((DownloadRecord d) => d.wallpaper.id == wallpaper.id)
      ..add(
        DownloadRecord(
          wallpaper: wallpaper,
          tier: tier,
          location: location,
          downloadedAt: DateTime(2026, 7, 14),
        ),
      );
  }
}
