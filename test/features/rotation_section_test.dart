import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/rotation_plan.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/settings/rotation_section.dart';

import '../fakes/fake_wallpaper_rotation.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeWallpaperRotation rotation,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallpaperRotationProvider.overrideWithValue(rotation),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: RotationSection())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('is off, and offers no choices, until it is switched on', (
    WidgetTester tester,
  ) async {
    // Choosing an interval for a rotation that is not running would be
    // configuring nothing.
    await _pump(tester, FakeWallpaperRotation());

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('How often'), findsNothing);
  });

  testWidgets('starts on the least surprising plan', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperRotation rotation = FakeWallpaperRotation();
    await _pump(tester, rotation);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    // Daily, from the gallery, onto the home screen — and explicitly *not* the
    // private library, which a rotation would put where anyone can see it.
    expect(rotation.started.single, RotationPlan.defaults);
    expect(rotation.started.single.source, RotationSource.gallery);
  });

  testWidgets('reads the schedule off the platform, not its own settings', (
    WidgetTester tester,
  ) async {
    // A restored backup or a cleared database would otherwise leave the switch
    // claiming a schedule the platform does not have.
    await _pump(
      tester,
      FakeWallpaperRotation(
        scheduled: const RotationPlan(
          interval: RotationInterval.hourly,
          source: RotationSource.privateLibrary,
          target: WallpaperTarget.both,
        ),
      ),
    );

    expect(
      find.textContaining('Every hour', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('says plainly what the private library means here', (
    WidgetTester tester,
  ) async {
    // "Private library" does not say it; a rotation puts its pick on a screen
    // anyone glancing at the phone sees.
    await _pump(
      tester,
      FakeWallpaperRotation(
        scheduled: const RotationPlan(
          interval: RotationInterval.daily,
          source: RotationSource.privateLibrary,
          target: WallpaperTarget.home,
        ),
      ),
    );

    expect(
      find.text(
        'Explicit wallpapers will appear on your home or lock screen.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('never warns about a source that is not the private one', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      FakeWallpaperRotation(scheduled: RotationPlan.defaults),
    );

    expect(
      find.text(
        'Explicit wallpapers will appear on your home or lock screen.',
      ),
      findsNothing,
    );
  });

  testWidgets('re-enqueues when one choice changes', (
    WidgetTester tester,
  ) async {
    // The platform has no notion of editing periodic work, so a reshape that
    // did not start again would leave the old schedule running while the
    // screen claimed the new one.
    final FakeWallpaperRotation rotation = FakeWallpaperRotation(
      scheduled: RotationPlan.defaults,
    );
    await _pump(tester, rotation);

    await tester.tap(find.byType(DropdownButton<RotationInterval>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every hour').last);
    await tester.pumpAndSettle();

    expect(rotation.started.single.interval, RotationInterval.hourly);
    // Only the interval moved; the rest of the plan is carried, not reset.
    expect(rotation.started.single.source, RotationPlan.defaults.source);
    expect(rotation.started.single.target, RotationPlan.defaults.target);
  });

  testWidgets('switching off stops the schedule', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperRotation rotation = FakeWallpaperRotation(
      scheduled: RotationPlan.defaults,
    );
    await _pump(tester, rotation);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(rotation.stops, 1);
    expect(find.text('Off'), findsOneWidget);
  });
}
