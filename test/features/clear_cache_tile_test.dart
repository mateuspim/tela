import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/features/settings/clear_cache_tile.dart';

import '../fakes/fake_fetched_image_cache.dart';

void main() {
  group('formatBytes', () {
    test('says what a storage screen says', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      // The figure that makes someone press the button.
      expect(formatBytes(2040109465), '1.9 GB');
      expect(formatBytes(15 * 1024 * 1024), '15.0 MB');
    });

    test('does not round a real cache down to nothing', () {
      // A tile reading "0 B" is a tile that looks broken and cannot be pressed.
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1024), isNot(contains('0 B')));
    });
  });

  testWidgets('names the real figure it would free', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeFetchedImageCache(bytes: 2040109465));

    expect(find.text('Clear image cache'), findsOneWidget);
    expect(find.textContaining('1.9 GB'), findsOneWidget);
    // The reassurance is the feature: the tier storage is not this.
    expect(find.textContaining('Downloads are not touched'), findsOneWidget);
  });

  testWidgets('clearing empties the cache and re-reads the figure', (
    WidgetTester tester,
  ) async {
    final FakeFetchedImageCache cache = FakeFetchedImageCache(
      bytes: 15 * 1024 * 1024,
    );
    await _pump(tester, cache);

    await tester.tap(find.byKey(const Key('settings-clear-cache')));
    await tester.pumpAndSettle();

    expect(cache.cleared, isTrue);
    expect(find.text('Image cache cleared.'), findsOneWidget);
    // Re-read, not remembered: the tile now shows the emptied cache.
    expect(find.textContaining('0 B'), findsOneWidget);
  });

  testWidgets('an empty cache offers nothing to press', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakeFetchedImageCache());

    final ListTile tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.onTap, isNull, reason: 'nothing to free is nothing to do');
  });
}

Future<void> _pump(WidgetTester tester, FakeFetchedImageCache cache) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        fetchedImageCacheProvider.overrideWithValue(cache),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ClearCacheTile()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
