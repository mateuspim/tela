import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps `Override` out of the default export surface.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/ports/notification_access.dart';
import 'package:tela/features/settings/notifications_tile.dart';

import '../fakes/fake_app_visibility.dart';

void main() {
  testWidgets('says so when notifications are on', (WidgetTester tester) async {
    await _pump(tester, _FakeNotificationAccess(enabled: true));

    expect(find.textContaining('On.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('says so when they are off', (WidgetTester tester) async {
    await _pump(tester, _FakeNotificationAccess());

    expect(find.textContaining('Off.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('a tap opens Android’s own page', (WidgetTester tester) async {
    final _FakeNotificationAccess access = _FakeNotificationAccess();
    await _pump(tester, access);

    await tester.tap(find.byKey(const Key('settings-notifications')));
    await tester.pumpAndSettle();

    expect(access.opened, 1);
  });

  /// The row must not assert all is well when it could not ask. Off is the
  /// reading that still offers the way to fix it.
  testWidgets('an unanswerable check reads as off', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _FakeNotificationAccess(throws: true));

    expect(find.textContaining('Off.'), findsOneWidget);
  });

  testWidgets('a page that will not open says so', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _FakeNotificationAccess(opens: false));

    await tester.tap(find.byKey(const Key('settings-notifications')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeNotificationAccess access,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        notificationAccessProvider.overrideWithValue(access),
        appVisibilityProvider.overrideWithValue(FakeAppVisibility()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: NotificationsTile()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeNotificationAccess implements NotificationAccess {
  _FakeNotificationAccess({
    this.enabled = false,
    this.opens = true,
    this.throws = false,
  });

  final bool enabled;
  final bool opens;
  final bool throws;
  int opened = 0;

  @override
  Future<bool> areEnabled() async {
    if (throws) throw StateError('no channel');
    return enabled;
  }

  @override
  Future<bool> openSettings() async {
    opened++;
    return opens;
  }
}
