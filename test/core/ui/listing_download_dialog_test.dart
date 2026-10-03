import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/listing_download_dialog.dart';
import 'package:tela/domain/models/listing_download_size.dart';

/// The confirmation is this feature's safety, not its politeness.
///
/// "Download all from @dude" and "download all from #anime" are one gesture
/// over a hundredfold difference in commitment — a few hundred megabytes
/// against tens of gigabytes — and nothing else on the screen tells them apart.
void main() {
  testWidgets('puts the count and the size in front of the user', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      const ListingDownloadSize(wallpapers: 12431, bytes: 54000000000),
    );

    expect(find.text('Download all from #anime?'), findsOne);
    expect(find.textContaining('12,431 wallpapers'), findsOne);
    expect(find.textContaining('50.3 GB'), findsOne);
  });

  testWidgets('a source that does not count says so, inventing nothing', (
    WidgetTester tester,
  ) async {
    // Konachan publishes no listing metadata at all. A number here would be a
    // fabrication about the only fact the dialog exists to state.
    await _open(tester, const ListingDownloadSize.uncounted());

    expect(
      find.text(
        'This source does not say how many wallpapers this listing holds.',
      ),
      findsOne,
    );
    expect(find.widgetWithText(FilledButton, 'Download'), findsOne);
  });

  testWidgets('an empty listing offers no download button at all', (
    WidgetTester tester,
  ) async {
    // A confirm button that would queue nothing is a button that lies about
    // what it does.
    await _open(
      tester,
      const ListingDownloadSize(wallpapers: 0, bytes: null),
    );

    expect(find.text('This listing has no wallpapers to download.'), findsOne);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('answers false when the user backs out', (
    WidgetTester tester,
  ) async {
    final List<bool> answers = <bool>[];
    await _open(
      tester,
      const ListingDownloadSize(wallpapers: 10, bytes: 100),
      onAnswer: ({required bool confirmed}) => answers.add(confirmed),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, <bool>[false]);
  });

  testWidgets('answers true only on the confirm button', (
    WidgetTester tester,
  ) async {
    final List<bool> answers = <bool>[];
    await _open(
      tester,
      const ListingDownloadSize(wallpapers: 10, bytes: 100),
      onAnswer: ({required bool confirmed}) => answers.add(confirmed),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    expect(answers, <bool>[true]);
  });
}

Future<void> _open(
  WidgetTester tester,
  ListingDownloadSize size, {
  void Function({required bool confirmed})? onAnswer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async {
            final bool answer = await confirmListingDownload(
              context,
              listing: '#anime',
              size: size,
            );
            onAnswer?.call(confirmed: answer);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
