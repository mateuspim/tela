import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// How much disk the fetched-image cache is using right now.
///
/// autoDispose and re-read on each visit: the figure is only true for as long
/// as nobody browses, and a stale "1.9 GB" on a cache that was cleared minutes
/// ago is worse than no figure at all.
final FutureProvider<int> cachedImageBytesProvider =
    FutureProvider.autoDispose<int>((Ref ref) {
      return ref.read(fetchedImageCacheProvider).sizeInBytes();
    });

/// Empties the disk cache of images fetched from Wallhaven, and says how much
/// that would free.
///
/// **Unconfirmed, deliberately** — unlike deleting a private file or forgetting
/// a history row, both of which ask first. Nothing here is the user's: every
/// byte is a copy of a file Wallhaven still serves, so the worst case is a
/// slower scroll. A confirmation would imply a loss that cannot happen.
class ClearCacheTile extends ConsumerWidget {
  /// Creates the tile.
  const ClearCacheTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int bytes = ref.watch(cachedImageBytesProvider).value ?? 0;
    return ListTile(
      key: const Key('settings-clear-cache'),
      leading: const Icon(Icons.cleaning_services_outlined),
      title: Text(l10n.settingsClearCache),
      subtitle: Text(l10n.settingsClearCacheSize(formatBytes(bytes))),
      trailing: const Icon(Icons.chevron_right),
      onTap: bytes == 0 ? null : () => _clear(context, ref),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String confirmation = AppLocalizations.of(
      context,
    ).settingsCacheCleared;
    await ref.read(fetchedImageCacheProvider).clear();
    ref.invalidate(cachedImageBytesProvider);
    messenger.showSnackBar(SnackBar(content: Text(confirmation)));
  }
}

/// Renders [bytes] the way a storage screen does: `0 B`, `12 KB`, `1.9 GB`.
///
/// One decimal place from MB up, and none below: "1.9 GB" is the number that
/// makes someone press the button, and "1.9 KB" of precision on a rounding
/// error is noise.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double size = bytes / 1024;
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final String rendered = unit == 0
      ? size.round().toString()
      : size.toStringAsFixed(1);
  return '$rendered ${units[unit]}';
}
