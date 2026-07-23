import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';

void main() {
  group('chooseDownloadDestination', () {
    // The point of the redesign: it is centred, not at the bottom edge. Pinned
    // structurally because "it looks centred" is not something a test can see.
    testWidgets('is a dialog, not a bottom sheet', (WidgetTester tester) async {
      await _open(tester, Purity.sfw);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('offers every destination with what it means', (
      WidgetTester tester,
    ) async {
      await _open(tester, Purity.sfw);

      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.text('Private library'), findsOneWidget);
      // The consequence line is the reason these are cards and not menu rows.
      expect(
        find.text('Visible in Photos and other gallery apps.'),
        findsOneWidget,
      );
    });

    // The invariant lives in StorageSettings.choicesFor, and this is the proof
    // the dialog asks it rather than listing the tiers itself.
    testWidgets('never offers the gallery for an explicit wallpaper', (
      WidgetTester tester,
    ) async {
      await _open(tester, Purity.nsfw);

      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.text('Private library'), findsOneWidget);
    });

    testWidgets('names the purity when there is something to warn about', (
      WidgetTester tester,
    ) async {
      await _open(tester, Purity.sketchy);
      expect(find.text('Sketchy'), findsOneWidget);
    });

    // A safe wallpaper has nothing to warn about, and a warning line on every
    // download would stop meaning anything.
    testWidgets('stays quiet for a safe wallpaper', (
      WidgetTester tester,
    ) async {
      await _open(tester, Purity.sfw);
      expect(find.text('Safe'), findsNothing);
    });

    testWidgets('resolves to the destination that was tapped', (
      WidgetTester tester,
    ) async {
      final Future<StorageTier?> picked = await _open(tester, Purity.sfw);

      await tester.tap(find.text('Private library'));
      await tester.pumpAndSettle();

      expect(await picked, StorageTier.appPrivate);
    });

    testWidgets('resolves to null when cancelled', (
      WidgetTester tester,
    ) async {
      final Future<StorageTier?> picked = await _open(tester, Purity.sfw);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await picked, isNull);
    });
  });
}

/// Pumps a host app and opens the dialog from a real context, returning the
/// pending pick. Called outside any tester-driven tap so the dialog's future is
/// not orphaned inside flutter_test's guarded zone — same reason as the volume
/// sheet's own harness.
Future<Future<StorageTier?>> _open(WidgetTester tester, Purity purity) async {
  await tester.pumpWidget(
    const MaterialApp(
      localizationsDelegates: <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox.expand()),
    ),
  );
  final BuildContext context = tester.element(find.byType(Scaffold));
  final Future<StorageTier?> picked = chooseDownloadDestination(
    context,
    purity,
  );
  await tester.pumpAndSettle();
  return picked;
}
