import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/source_id.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';
import 'package:tela/features/browse/browse_filter_scope.dart';
import 'package:tela/features/browse/filter_sheet.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_wallpaper_source.dart';

/// The sheet renders *from* the active source's capabilities.
///
/// The failure mode this is designed against is the obvious alternative:
/// offering a filter the source cannot honour and silently dropping it, which
/// looks to the user like the app ignoring them.
void main() {
  testWidgets('Wallhaven gets the whole vocabulary', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, FakeWallpaperSource());

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Purity'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Top list range'), findsOneWidget);
  });

  testWidgets('a narrower source is offered only what it can honour', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      FakeWallpaperSource(
        id: const SourceId('booru'),
        displayName: 'Booru',
        capabilities: narrowCapabilities,
      ),
    );

    // A booru has no general/anime/people axis and publishes no colour data,
    // and nothing here has a toplist window.
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Color'), findsNothing);
    expect(find.text('Top list range'), findsNothing);
    // The whole "Appearance" card goes with its one group: a heading promising
    // filters that are not there is worse than no heading.
    expect(find.text('Appearance'), findsNothing);
    // What it does support is untouched.
    expect(find.text('Purity'), findsOneWidget);
    expect(find.text('Shape'), findsOneWidget);
  });
}

/// Mounts the sheet with [source] as the only registered source.
Future<void> _pumpSheet(WidgetTester tester, WallpaperSource source) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallpaperSourcesProvider.overrideWithValue(<WallpaperSource>[source]),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        secretStoreProvider.overrideWithValue(
          FakeSecretStore(storedKey: 'abc123'),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FilterSheet(scope: _StaticScope())),
      ),
    ),
  );
  await tester.pump();
}

/// A shelf that holds one query and forgets what is applied to it — the sheet's
/// only collaborator, and none of what this test asserts depends on it.
class _StaticScope implements BrowseFilterScope {
  @override
  SearchQuery get filters => const SearchQuery();

  SearchQuery get defaultQuery => const SearchQuery();

  @override
  void applyFilters(SearchQuery filters) {}

  @override
  void clearFilters() {}
}
