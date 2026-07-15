import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_status_view.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/features/settings/blocked_tags_providers.dart';

/// Every tag blocked from a detail screen, each one tap away from unblocked.
///
/// Unblocking asks no confirmation, unlike the download-history removal: it
/// only widens what a future search can show, and re-blocking the same tag
/// costs one long press, so there is nothing here a stray tap can't undo.
class BlockedTagsScreen extends ConsumerWidget {
  /// Creates the blocked-tags management screen.
  const BlockedTagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<WallpaperTag>> blocked = ref.watch(
      blockedTagsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          l10n.blockedTagsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: blocked.when(
        data: (List<WallpaperTag> tags) => _list(ref, l10n, tags),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => WallpaperStatusView(
          icon: Icons.error_outline,
          message: l10n.errorUnexpected,
        ),
      ),
    );
  }

  Widget _list(WidgetRef ref, AppLocalizations l10n, List<WallpaperTag> tags) {
    if (tags.isEmpty) {
      return WallpaperStatusView(
        icon: Icons.label_off_outlined,
        message: l10n.blockedTagsEmpty,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tags.length,
      separatorBuilder: (BuildContext context, int index) => const Divider(),
      itemBuilder: (BuildContext context, int index) =>
          _tile(ref, l10n, tags[index]),
    );
  }

  Widget _tile(WidgetRef ref, AppLocalizations l10n, WallpaperTag tag) {
    return ListTile(
      leading: const Icon(Icons.label_off_outlined),
      title: Text(tag.name),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.blockedTagsUnblock(tag.name),
        onPressed: () => _unblock(ref, tag),
      ),
    );
  }

  Future<void> _unblock(WidgetRef ref, WallpaperTag tag) async {
    await ref.read(tagBlocklistRepositoryProvider).unblock(tag.id);
    refreshBlockedTags(ref);
  }
}
