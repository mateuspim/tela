import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/download_record.dart';
import 'package:tela/domain/ports/download_history.dart';

/// Every recorded download, newest first — the history grid's whole source.
///
/// Reads from SQLite, never from Wallhaven, so it resolves offline. Explicit
/// downloads are not in here: they live in the private library.
final FutureProvider<List<DownloadRecord>> recentDownloadsProvider =
    FutureProvider<List<DownloadRecord>>((Ref ref) {
      final DownloadHistory history = ref.watch(downloadHistoryProvider);
      return history.downloads();
    });
