import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/ports/tag_blocklist_repository.dart';

/// Every blocked tag, most recently blocked first — the management screen's
/// whole source.
final FutureProvider<List<WallpaperTag>> blockedTagsProvider =
    FutureProvider<List<WallpaperTag>>((Ref ref) {
      final TagBlocklistRepository blocklist = ref.watch(
        tagBlocklistRepositoryProvider,
      );
      return blocklist.all();
    });

/// Re-reads the blocklist after a write.
///
/// Blocking a tag from the detail screen must also change the management
/// screen behind it; a plain (non-autoDispose) future resolves once and then
/// caches, so without this the new block would sit in SQLite but not on
/// screen until the next cold start — the same staleness the favorites
/// refresh exists to avoid.
void refreshBlockedTags(WidgetRef ref) {
  ref.invalidate(blockedTagsProvider);
}
