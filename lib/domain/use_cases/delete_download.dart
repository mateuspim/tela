import 'package:tela/domain/models/download_deletion.dart';
import 'package:tela/domain/models/image_store_failure.dart';
import 'package:tela/domain/models/storage_tier.dart';
import 'package:tela/domain/models/wallpaper_ref.dart';
import 'package:tela/domain/ports/download_history.dart';
import 'package:tela/domain/ports/image_store.dart';

/// Deletes a downloaded wallpaper from everywhere it is: the file *and* the
/// history row.
///
/// The one delete path for the whole app — the download history, the private
/// library, and the detail screen all run through here, so "delete from device"
/// means the same thing wherever it is tapped, and there is one place the file
/// order and the history order are decided.
///
/// ```dart
/// await deleteDownload(ref: record.wallpaper.ref, tier: record.tier,
///     location: record.location);
/// ```
class DeleteDownload {
  /// Creates the use case over the storage and history seams.
  const DeleteDownload({
    required ImageStore imageStore,
    required DownloadHistory history,
  }) : _imageStore = imageStore,
       _history = history;

  final ImageStore _imageStore;
  final DownloadHistory _history;

  /// Deletes the file, then forgets the row — but only once the file is gone.
  ///
  /// The order is load-bearing: forgetting first would strand the file with no
  /// row to reach it from if the delete then failed. And `forget` is a no-op
  /// for a wallpaper it never held (every app-private download, which is
  /// never recorded), so the private library shares this path for free.
  ///
  /// [ref] is null for a file with no history row to forget — every
  /// app-private image, which is deliberately never recorded. Required rather
  /// than defaulted, so a caller that *does* hold one cannot quietly skip it
  /// and strand a row pointing at a file that is gone.
  ///
  /// A [DownloadDeletion.declined] — the user dismissing the system prompt —
  /// leaves both the file and the row exactly as they were.
  Future<DownloadDeletion> call({
    required WallpaperRef? ref,
    required StorageTier tier,
    required Uri location,
  }) async {
    final DownloadDeletion deletion = await _deleteFile(tier, location);
    final WallpaperRef? recorded = ref;
    if (deletion == DownloadDeletion.deleted && recorded != null) {
      await _history.forget(recorded);
    }
    return deletion;
  }

  /// Deletes the file, treating an already-gone file as a deletion rather than
  /// an error.
  ///
  /// A history row can outlive its file — Photos or a file manager deleted it
  /// behind tela's back, which is exactly what the missing badge marks. Such a
  /// row must still delete and forget; a failure whose file cannot be read
  /// anyway *is* the end state we wanted, so it resolves to deleted. A failure
  /// whose file is still readable is a real one and rethrows.
  Future<DownloadDeletion> _deleteFile(StorageTier tier, Uri location) async {
    try {
      return await _imageStore.deleteDownload(tier: tier, location: location);
    } on ImageStoreFailure {
      if (await _imageStore.canRead(location)) rethrow;
      return DownloadDeletion.deleted;
    }
  }
}
