import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_volume_sheet.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

void main() {
  group('chooseDownloadVolume', () {
    testWidgets('offers the card only when one is available', (
      WidgetTester tester,
    ) async {
      final Future<StorageVolumeKind?> picked = await _open(
        tester,
        offerSdCard: false,
      );
      expect(find.text('Internal storage'), findsOneWidget);
      expect(find.text('SD card'), findsNothing);

      await _tap(tester, 'Internal storage');
      expect(await picked, StorageVolumeKind.device);
    });

    testWidgets('offers both volumes when a card is on offer', (
      WidgetTester tester,
    ) async {
      final Future<StorageVolumeKind?> picked = await _open(
        tester,
        offerSdCard: true,
      );
      expect(find.text('Internal storage'), findsOneWidget);
      expect(find.text('SD card'), findsOneWidget);

      await _tap(tester, 'Internal storage');
      expect(await picked, StorageVolumeKind.device);
    });

    testWidgets('resolves to the volume that was tapped', (
      WidgetTester tester,
    ) async {
      final Future<StorageVolumeKind?> picked = await _open(
        tester,
        offerSdCard: true,
      );
      await _tap(tester, 'SD card');
      expect(await picked, StorageVolumeKind.sdCard);
    });

    testWidgets('resolves to null when dismissed', (
      WidgetTester tester,
    ) async {
      final Future<StorageVolumeKind?> picked = await _open(
        tester,
        offerSdCard: true,
      );
      // Popping the modal route is exactly what a barrier tap or back does.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(await picked, isNull);
    });
  });
}

/// Pumps a host app and opens the sheet from a real context, returning the
/// pending pick. Called outside any tester-driven tap so the sheet's future is
/// not orphaned inside flutter_test's guarded zone.
Future<Future<StorageVolumeKind?>> _open(
  WidgetTester tester, {
  required bool offerSdCard,
}) async {
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
  final Future<StorageVolumeKind?> picked = chooseDownloadVolume(
    context,
    offerSdCard: offerSdCard,
  );
  await tester.pumpAndSettle();
  return picked;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
