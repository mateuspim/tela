import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Hard-deletes a batch of downloads — their files and their history rows.
///
/// The bulk sibling of `DeleteDownload`, for the history's multi-select bar.
/// It is not a loop over the single delete: it hands the whole selection to
/// [ImageStore.deleteDownloads] so the gallery tier resolves to one system
/// prompt rather than one per file, then forgets only the rows whose files
/// actually went — a declined prompt leaves that subset, files and rows,
/// exactly as they were.
///
/// ```dart
/// final int gone = await deleteDownloads(selectedRecords);
/// ```
class DeleteDownloads {
  /// Creates the use case over the storage and history seams.
  const DeleteDownloads({
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _history = history;

  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// Deletes every file in [records], forgets the rows that went, and answers
  /// how many actually went — the "3 of 5" the caller reports.
  Future<int> call(List<DownloadRecord> records) async {
    if (records.isEmpty) return 0;
    final Set<Uri> deleted = await _imageStore.deleteDownloads(
      <({StorageTier tier, Uri location})>[
        for (final DownloadRecord record in records)
          (tier: record.tier, location: record.location),
      ],
    );
    for (final DownloadRecord record in records) {
      if (deleted.contains(record.location)) {
        await _history.forget(record.wallpaper.id);
      }
    }
    return deleted.length;
  }
}
