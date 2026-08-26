import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/vault_folder.dart';
import 'package:tela/features/settings/vault_folder_section.dart';

import '../fakes/fake_image_store.dart';

void main() {
  testWidgets('names the hidden folder the platform reports', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore()..vault = VaultFolder('stash');
    await _pump(tester, store);

    expect(find.textContaining('.stash'), findsOneWidget);
  });

  testWidgets('falls back to the standard vault before anything is set', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore());

    expect(find.textContaining('.tela'), findsOneWidget);
  });

  testWidgets('renaming stores the label without its dot', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore();
    await _pump(tester, store);

    await _rename(tester, 'stash');

    expect(store.vault, VaultFolder('stash'));
    expect(find.textContaining('.stash'), findsOneWidget);
  });

  /// The dot is a fixed prefix on the field, so someone typing the folder they
  /// can see must not end up with `..stash`.
  testWidgets('a typed leading dot is absorbed, never doubled', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore();
    await _pump(tester, store);

    await _rename(tester, '.stash');

    expect(store.vault.directoryName, '.stash');
  });

  testWidgets('a name that cannot be a folder cannot be saved', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore();
    await _pump(tester, store);

    await tester.tap(find.byKey(const Key('settings-vault-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vault-folder-field')), '..');
    await tester.pumpAndSettle();

    expect(find.text('That cannot be a folder name.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(store.vault, VaultFolder.standard);
  });

  testWidgets('dismissing the dialog changes nothing', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore();
    await _pump(tester, store);

    await tester.tap(find.byKey(const Key('settings-vault-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vault-folder-field')), 'x');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(store.vault, VaultFolder.standard);
  });

  /// A refusal from the platform is not something the user can correct — the
  /// label was valid — so it is reported rather than shown as a field error.
  testWidgets('a storage failure is reported and the row does not move', (
    WidgetTester tester,
  ) async {
    final FakeImageStore store = FakeImageStore()..vaultWriteFails = true;
    await _pump(tester, store);

    await _rename(tester, 'stash');

    expect(find.text('Could not save the folder name.'), findsOneWidget);
    expect(find.textContaining('.tela'), findsOneWidget);
  });

  /// The one thing a user must not conclude from "hidden": that the images are
  /// gone from the app, or that this is a lock.
  testWidgets('the rename dialog states the limit and the reassurance', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeImageStore());

    await tester.tap(find.byKey(const Key('settings-vault-folder')));
    await tester.pumpAndSettle();

    expect(find.textContaining('concealment, not a lock'), findsOneWidget);
    expect(find.textContaining('private library'), findsOneWidget);
    expect(find.textContaining('stay there'), findsOneWidget);
  });
}

Future<void> _rename(WidgetTester tester, String typed) async {
  await tester.tap(find.byKey(const Key('settings-vault-folder')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('vault-folder-field')), typed);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('vault-folder-save')));
  await tester.pumpAndSettle();
}

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('vault-folder-save')));

Future<void> _pump(WidgetTester tester, FakeImageStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[imageStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(
        home: Scaffold(body: VaultFolderSection()),
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
