import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/storage_volume_kind_text.dart';
import 'package:tela/domain/models/storage_volume_kind.dart';

void main() {
  group('storage volume kind text', () {
    testWidgets('names and describes each volume', (WidgetTester tester) async {
      final AppLocalizations l10n = await _load(tester);

      expect(
        storageVolumeLabel(l10n, StorageVolumeKind.device),
        'Internal storage',
      );
      expect(storageVolumeLabel(l10n, StorageVolumeKind.sdCard), 'SD card');
      expect(
        storageVolumeDetail(l10n, StorageVolumeKind.device),
        'Built-in device storage',
      );
      expect(
        storageVolumeDetail(l10n, StorageVolumeKind.sdCard),
        'Removable memory card',
      );
    });

    // The Settings chooser and the download-time sheet both draw from this, so
    // a swap here silently changes both — pin the icons.
    test('gives each volume its own icon', () {
      expect(storageVolumeIcon(StorageVolumeKind.device), Icons.smartphone);
      expect(
        storageVolumeIcon(StorageVolumeKind.sdCard),
        Icons.sd_card_outlined,
      );
    });
  });
}

/// Pumps a localized host and returns its [AppLocalizations].
Future<AppLocalizations> _load(WidgetTester tester) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) {
          l10n = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return l10n;
}
