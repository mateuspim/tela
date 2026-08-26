import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/source_capabilities.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/models/wallpaper_collection.dart';
import 'package:tela/features/browse/collections_screen.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

const CollectionRef _interiors = CollectionRef(
  source: SourceId.wallhaven,
  owner: 'jrmnt',
  id: '1797738',
);

const CollectionRef _secret = CollectionRef(
  source: SourceId.wallhaven,
  owner: 'jrmnt',
  id: '999',
);

const List<WallpaperCollection> _theirs = <WallpaperCollection>[
  WallpaperCollection(
    ref: _interiors,
    label: 'Interiors',
    count: 49,
    isPublic: true,
    views: 5201,
  ),
  WallpaperCollection(
    ref: _secret,
    label: 'Unlisted',
    count: 3,
    isPublic: false,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  String? username,
  String? storedUsername,
  SourceCapabilities capabilities = wallhavenLikeCapabilities,
  Map<String, List<WallpaperCollection>> collections =
      const <String, List<WallpaperCollection>>{},
}) async {
  final FakeWallpaperSource source = FakeWallpaperSource(
    capabilities: capabilities,
    collections: collections,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository()..collectionsUsername = storedUsername,
        ),
        secretStoreProvider.overrideWithValue(FakeSecretStore()),
        wallhavenSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CollectionsScreen(username: username),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("lists an account's collections with their real sizes", (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      username: 'jrmnt',
      collections: <String, List<WallpaperCollection>>{'jrmnt': _theirs},
    );

    expect(find.text('Interiors'), findsOneWidget);
    // The collection's own count, not what a purity filter would leave — see
    // WallpaperCollection, where the two numbers are deliberately different.
    expect(find.text('49 wallpapers'), findsOneWidget);
  });

  testWidgets('marks a private collection, and only that one', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      username: 'jrmnt',
      collections: <String, List<WallpaperCollection>>{'jrmnt': _theirs},
    );

    // The point of carrying isPublic into the domain: someone reading their
    // own collections needs to see which of them strangers can read.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('says what to do when no username is stored', (
    WidgetTester tester,
  ) async {
    // The whole reason NoCollectionsUsernameFailure exists rather than reusing
    // a 404: this sentence names an action, where "not found" would blame an
    // account the user never typed.
    await _pump(tester);

    expect(
      find.textContaining('username', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('reads the stored username for your own collections', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      storedUsername: 'jrmnt',
      collections: <String, List<WallpaperCollection>>{'jrmnt': _theirs},
    );

    expect(find.text('My collections'), findsOneWidget);
    expect(find.text('Interiors'), findsOneWidget);
  });

  testWidgets('says an account publishes nothing, without guessing why', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      username: 'nobody',
      collections: <String, List<WallpaperCollection>>{
        'nobody': <WallpaperCollection>[],
      },
    );

    expect(find.text('No collections here.'), findsOneWidget);
  });
}
