import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_tag_field.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// The tag row in the download chooser: which folder a download is filed under.
///
/// The rule worth pinning here is the one that is invisible on screen — a tag
/// the user typed a moment ago has no folder behind it yet, so a row that
/// listed only *existing* folders would drop the selection the instant it was
/// made.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required TagFolder? selected,
    required List<TagFolder> known,
    required void Function(TagFolder?) onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DownloadTagField(
            selected: selected,
            known: known,
            onChanged: onChanged,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers every known tag, plus None and New', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      selected: null,
      known: <TagFolder>[TagFolder('anime'), TagFolder('minimal')],
      onChanged: (TagFolder? _) {},
    );

    expect(find.text('anime'), findsOneWidget);
    expect(find.text('minimal'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('New tag'), findsOneWidget);
  });

  testWidgets('tapping a tag reports it, and None reports null', (
    WidgetTester tester,
  ) async {
    final List<TagFolder?> chosen = <TagFolder?>[];
    await pump(
      tester,
      selected: TagFolder('anime'),
      known: <TagFolder>[TagFolder('anime')],
      onChanged: chosen.add,
    );

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('anime'));
    await tester.pumpAndSettle();

    expect(chosen, <TagFolder?>[null, TagFolder('anime')]);
  });

  /// Nothing has been downloaded into a just-typed tag, so it is in no listing
  /// yet. Without this it would vanish from its own row on being chosen.
  testWidgets('shows a selected tag that is not yet a folder', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      selected: TagFolder('brand new'),
      known: <TagFolder>[TagFolder('anime')],
      onChanged: (TagFolder? _) {},
    );

    expect(find.text('brand new'), findsOneWidget);
    expect(find.text('anime'), findsOneWidget);
  });

  group('naming a new tag', () {
    testWidgets('accepts a legal name and reports it', (
      WidgetTester tester,
    ) async {
      final List<TagFolder?> chosen = <TagFolder?>[];
      await pump(
        tester,
        selected: null,
        known: const <TagFolder>[],
        onChanged: chosen.add,
      );

      await tester.tap(find.text('New tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sci fi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use tag'));
      await tester.pumpAndSettle();

      expect(chosen, <TagFolder?>[TagFolder('sci fi')]);
    });

    /// Refused while it is being typed rather than on the way to disk: the rule
    /// is not guessable, and a dialog that takes a name and then loses it is
    /// the worse of the two ways to say so.
    testWidgets('cannot confirm a name that could not be a folder', (
      WidgetTester tester,
    ) async {
      final List<TagFolder?> chosen = <TagFolder?>[];
      await pump(
        tester,
        selected: null,
        known: const <TagFolder>[],
        onChanged: chosen.add,
      );

      await tester.tap(find.text('New tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '../secrets');
      await tester.pumpAndSettle();

      final TextButton use = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Use tag'),
      );
      expect(use.onPressed, isNull);
      expect(find.text('Letters, digits, spaces, _ and -'), findsWidgets);
      expect(chosen, isEmpty);
    });

    testWidgets('dismissing it changes nothing', (WidgetTester tester) async {
      final List<TagFolder?> chosen = <TagFolder?>[];
      await pump(
        tester,
        selected: null,
        known: const <TagFolder>[],
        onChanged: chosen.add,
      );

      await tester.tap(find.text('New tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(chosen, isEmpty);
    });
  });
}
