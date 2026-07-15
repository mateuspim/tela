import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/features/settings/blocked_tags_screen.dart';

import '../fakes/fake_tag_blocklist_repository.dart';

void main() {
  testWidgets('teaches the long-press gesture when nothing is blocked', (
    WidgetTester tester,
  ) async {
    await _pumpBlockedTags(tester, FakeTagBlocklistRepository());

    expect(
      find.textContaining('Long-press a tag on any wallpaper'),
      findsOneWidget,
    );
  });

  testWidgets('lists every blocked tag, most recently blocked first', (
    WidgetTester tester,
  ) async {
    await _pumpBlockedTags(
      tester,
      FakeTagBlocklistRepository(
        initial: const <WallpaperTag>[
          WallpaperTag(id: 1, name: 'older'),
          WallpaperTag(id: 2, name: 'newer'),
        ],
      ),
    );

    final Finder tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(
      tester.widget<ListTile>(tiles.at(0)).title,
      isA<Text>().having((Text t) => t.data, 'text', 'newer'),
    );
    expect(
      tester.widget<ListTile>(tiles.at(1)).title,
      isA<Text>().having((Text t) => t.data, 'text', 'older'),
    );
  });

  testWidgets('unblocking a tag removes it with no confirmation', (
    WidgetTester tester,
  ) async {
    final FakeTagBlocklistRepository blocklist = FakeTagBlocklistRepository(
      initial: const <WallpaperTag>[WallpaperTag(id: 37, name: 'nature')],
    );
    await _pumpBlockedTags(tester, blocklist);

    await tester.tap(find.byTooltip('Unblock nature'));
    await tester.pumpAndSettle();

    expect(find.text('nature'), findsNothing);
    expect(blocklist.blockedIds(), isEmpty);
  });
}

Future<void> _pumpBlockedTags(
  WidgetTester tester,
  FakeTagBlocklistRepository blocklist,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        tagBlocklistRepositoryProvider.overrideWithValue(blocklist),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlockedTagsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
