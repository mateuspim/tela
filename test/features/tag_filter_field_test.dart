import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/search_tag.dart';
import 'package:tela/features/browse/tag_filter_field.dart';

/// Boots the field over its real localizations, reporting each edit through
/// `onChanged` the way the filter sheet's `setState` would.
Future<List<SearchTag>> _pump(
  WidgetTester tester,
  List<SearchTag> value,
  void Function(List<SearchTag>) onChanged,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TagFilterField(value: value, onChanged: onChanged),
      ),
    ),
  );
  await tester.pump();
  return value;
}

void main() {
  group('TagFilterField', () {
    testWidgets('submitting the field adds the tag as an include', (
      WidgetTester tester,
    ) async {
      List<SearchTag> tags = <SearchTag>[];
      await _pump(tester, tags, (List<SearchTag> next) => tags = next);

      await tester.enterText(find.byType(TextField), 'nature');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(tags, <SearchTag>[const SearchTag('nature')]);
    });

    testWidgets('refuses a second entry of the same name, any case', (
      WidgetTester tester,
    ) async {
      List<SearchTag> tags = <SearchTag>[const SearchTag('nature')];
      await _pump(tester, tags, (List<SearchTag> next) => tags = next);

      await tester.enterText(find.byType(TextField), 'Nature');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      // A name cannot be both demanded and forbidden; the repeat is dropped so
      // the query never contradicts itself.
      expect(tags, <SearchTag>[const SearchTag('nature')]);
    });

    testWidgets('tapping a chip flips its sense', (WidgetTester tester) async {
      List<SearchTag> tags = <SearchTag>[const SearchTag('nature')];
      await _pump(tester, tags, (List<SearchTag> next) => tags = next);

      await tester.tap(find.text('nature'));
      await tester.pump();

      expect(tags, <SearchTag>[const SearchTag('nature', TagSense.exclude)]);
    });

    testWidgets('deleting a chip removes only that tag', (
      WidgetTester tester,
    ) async {
      List<SearchTag> tags = <SearchTag>[
        const SearchTag('nature'),
        const SearchTag('people', TagSense.exclude),
      ];
      await _pump(tester, tags, (List<SearchTag> next) => tags = next);

      // The delete affordance carries the tag's name in its tooltip.
      await tester.tap(find.byTooltip('Remove nature'));
      await tester.pump();

      expect(tags, <SearchTag>[const SearchTag('people', TagSense.exclude)]);
    });
  });
}
