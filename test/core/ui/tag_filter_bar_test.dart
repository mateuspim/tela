import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/tag_filter_bar.dart';
import 'package:tela/domain/models/tag_folder.dart';

/// Narrowing a library shelf to one tag.
///
/// The rule with teeth is that **Untagged is its own filter**. A library that
/// has been tagged for a while keeps a pile of older files in the tier root,
/// and folding them into *All* would leave "show me what I never filed"
/// unaskable — which is the question someone tidying up has.
void main() {
  group('TagFilter', () {
    test('all admits everything', () {
      const TagFilter filter = TagFilter.all();

      expect(filter.matches(TagFolder('anime')), isTrue);
      expect(filter.matches(null), isTrue);
      expect(filter.isAll, isTrue);
    });

    test('a tag admits only that tag', () {
      final TagFilter filter = TagFilter.of(TagFolder('anime'));

      expect(filter.matches(TagFolder('anime')), isTrue);
      expect(filter.matches(TagFolder('minimal')), isFalse);
      expect(filter.matches(null), isFalse);
      expect(filter.isAll, isFalse);
    });

    test('untagged admits only what is filed under nothing', () {
      const TagFilter filter = TagFilter.untagged();

      expect(filter.matches(null), isTrue);
      expect(filter.matches(TagFolder('anime')), isFalse);
      expect(filter.isAll, isFalse);
    });
  });

  group('TagFilterBar', () {
    Future<List<TagFilter>> pump(
      WidgetTester tester, {
      required List<TagFolder> tags,
      TagFilter selected = const TagFilter.all(),
      bool hasUntagged = true,
    }) async {
      final List<TagFilter> chosen = <TagFilter>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TagFilterBar(
              tags: tags,
              selected: selected,
              hasUntagged: hasUntagged,
              onChanged: chosen.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return chosen;
    }

    /// A filter offering only "everything" is a control that cannot do
    /// anything, and this screen has no vertical space to spare.
    testWidgets('is absent entirely when nothing is tagged', (
      WidgetTester tester,
    ) async {
      await pump(tester, tags: const <TagFolder>[]);

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('offers All, each tag, and Untagged', (
      WidgetTester tester,
    ) async {
      await pump(tester, tags: <TagFolder>[TagFolder('anime')]);

      expect(find.text('All'), findsOneWidget);
      expect(find.text('anime'), findsOneWidget);
      expect(find.text('Untagged'), findsOneWidget);
    });

    /// Nothing on the shelf is untagged, so the chip would filter to an empty
    /// grid every time.
    testWidgets('drops Untagged when everything is filed', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        tags: <TagFolder>[TagFolder('anime')],
        hasUntagged: false,
      );

      expect(find.text('Untagged'), findsNothing);
    });

    testWidgets('reports the tag that was tapped', (WidgetTester tester) async {
      final List<TagFilter> chosen = await pump(
        tester,
        tags: <TagFolder>[TagFolder('anime')],
      );

      await tester.tap(find.text('anime'));
      await tester.pumpAndSettle();

      expect(chosen, <TagFilter>[TagFilter.of(TagFolder('anime'))]);
    });

    /// Getting out of a filter never needs a hunt for the All chip.
    testWidgets('re-tapping the active chip clears back to everything', (
      WidgetTester tester,
    ) async {
      final List<TagFilter> chosen = await pump(
        tester,
        tags: <TagFolder>[TagFolder('anime')],
        selected: TagFilter.of(TagFolder('anime')),
      );

      await tester.tap(find.text('anime'));
      await tester.pumpAndSettle();

      expect(chosen, <TagFilter>[const TagFilter.all()]);
    });
  });
}
