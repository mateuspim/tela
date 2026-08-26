import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// The stored account name, and the way into that account's collections.
///
/// **The username is typed rather than discovered, and that is the source's
/// doing, not a shortcut.** Wallhaven's `/settings` returns no username, and
/// neither does its authenticated `/collections` — while the contents route is
/// addressed `/collections/{username}/{id}` (its own API reference, checked
/// 2026-08-26). So the bare own-collections route hands back ids it gives no
/// way to open, and one typed name is what closes that gap. With a key stored
/// too, the same request also returns the account's *private* collections.
final AsyncNotifierProvider<CollectionsUsernameController, String?>
collectionsUsernameProvider =
    AsyncNotifierProvider<CollectionsUsernameController, String?>(
      CollectionsUsernameController.new,
    );

/// Loads the stored username and writes an edit straight back through the port.
///
/// Same no-save-button shape as the other settings controllers: a screen that
/// can be closed mid-edit should not be able to lose the edit.
class CollectionsUsernameController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() {
    return ref.watch(settingsRepositoryProvider).loadCollectionsUsername();
  }

  /// Remembers [username], or forgets it when null or blank.
  Future<void> save(String? username) async {
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    // Written, then read back rather than echoed: the port owns the trimming
    // and blank-means-none rules, so reading back is what keeps this
    // controller from having a second, drifting opinion about them.
    await settings.setCollectionsUsername(username);
    state = AsyncData<String?>(await settings.loadCollectionsUsername());
  }
}

/// The collections settings rows: whose account, and a way to open it.
class CollectionsSection extends ConsumerWidget {
  /// Creates the collections section of the settings screen.
  const CollectionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Withheld entirely on a source with no collections, rather than shown
    // and failing on tap.
    if (!ref.watch(browseCollectionsProvider).isSupported) {
      return const SizedBox.shrink();
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? username = ref.watch(collectionsUsernameProvider).value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(l10n.settingsCollectionsUsername),
          subtitle: Text(
            username ?? l10n.settingsCollectionsUsernameHint,
          ),
          onTap: () => _edit(context, ref, username),
        ),
        ListTile(
          leading: const Icon(Icons.collections_bookmark_outlined),
          title: Text(l10n.collectionsMine),
          // Enabled even with no username stored: the screen names the missing
          // username itself (`errorNoCollectionsUsername`), which tells the
          // user what to do, where a dead row would only tell them nothing.
          onTap: () => context.pushNamed(TelaRoutes.collectionsName),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final String? entered = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _UsernameDialog(initial: current),
    );
    if (entered == null) return;
    await ref.read(collectionsUsernameProvider.notifier).save(entered);
  }
}

/// Asks for the account name, and nothing else.
class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.initial});

  final String? initial;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsCollectionsUsername),
      content: TextField(
        controller: _field,
        autofocus: true,
        autocorrect: false,
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
