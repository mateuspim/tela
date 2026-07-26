import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/domain/models/source_failure.dart';

/// Reads [localizedFailure] through a real [AppLocalizations], because the
/// point of the function is the sentence a person ends up seeing.
Future<String> _sentenceFor(
  WidgetTester tester,
  SourceFailure failure, {
  String sourceName = 'Wallhaven',
}) async {
  late String sentence;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) {
          sentence = localizedFailure(
            AppLocalizations.of(context),
            failure,
            sourceName: sourceName,
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return sentence;
}

void main() {
  group('localizedFailure', () {
    testWidgets('names the id and the source when nothing was found', (
      WidgetTester tester,
    ) async {
      // The id-jump chip's most likely failure is a typo, and a person who
      // typed six characters has to be able to see which six missed.
      final String sentence = await _sentenceFor(
        tester,
        NotFoundFailure('je9ldq'),
      );

      expect(sentence, contains('je9ldq'));
      expect(sentence, contains('Wallhaven'));
    });

    testWidgets('a not-found id does not read as a malfunction', (
      WidgetTester tester,
    ) async {
      // The whole reason NotFoundFailure exists rather than reusing
      // UnexpectedResponseFailure: these two must not say the same thing.
      final String notFound = await _sentenceFor(
        tester,
        NotFoundFailure('je9ldq'),
      );
      final String unexpected = await _sentenceFor(
        tester,
        const UnexpectedResponseFailure('bad json'),
      );

      expect(notFound, isNot(unexpected));
    });

    testWidgets('carries the source name into the other failures', (
      WidgetTester tester,
    ) async {
      expect(
        await _sentenceFor(
          tester,
          const NetworkFailure(),
          sourceName: 'Konachan',
        ),
        contains('Konachan'),
      );
      expect(
        await _sentenceFor(
          tester,
          const InvalidApiKeyFailure(),
          sourceName: 'Konachan',
        ),
        contains('Konachan'),
      );
    });

    testWidgets('never leaks the developer-facing message', (
      WidgetTester tester,
    ) async {
      // SourceFailure.message is for logs; it can name internals and must not
      // reach a screen.
      final String sentence = await _sentenceFor(
        tester,
        const UnexpectedResponseFailure('Wallhaven answered with status 500'),
      );

      expect(sentence, isNot(contains('500')));
    });
  });
}
