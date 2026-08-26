import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/ports/wallpaper_beam.dart';
import 'package:tela/features/beam/beam_sheet.dart';

import '../fakes/fake_multicast_lease.dart';
import '../fakes/fake_settings_repository.dart';

const BeamFile _file = BeamFile(
  id: 'wallhaven-aaaaaa',
  fileName: 'wallhaven-aaaaaa.jpg',
  path: '/cache/wallhaven-aaaaaa.jpg',
  sizeBytes: 10,
  mimeType: 'image/jpeg',
  purity: Purity.sfw,
);

const BeamTarget _desktop = BeamTarget(
  alias: 'workstation',
  host: '192.168.50.20',
  port: 53317,
  fingerprint: 'receiver-fp',
  usesHttps: false,
);

/// A beam whose discovery answers differently on each subscription.
///
/// The point of the fake: a "search again" that did not really re-subscribe
/// would keep showing the first answer forever, and a test over a fixed stream
/// could not tell the two apart.
class _ScriptedBeam implements WallpaperBeam {
  _ScriptedBeam(this._rounds);

  final List<List<BeamTarget>> _rounds;
  int subscriptions = 0;

  @override
  Stream<BeamTarget> discover() {
    final int round = subscriptions++;
    final List<BeamTarget> found = round < _rounds.length
        ? _rounds[round]
        : const <BeamTarget>[];
    return Stream<BeamTarget>.fromIterable(found);
  }

  @override
  Future<BeamTarget> sendTo({required String host, required int port}) async =>
      _desktop;

  @override
  Future<void> send({
    required BeamTarget target,
    required List<BeamFile> files,
    void Function(int bytesSent)? onProgress,
    String? pin,
  }) async {}
}

Future<void> _pump(WidgetTester tester, _ScriptedBeam beam) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallpaperBeamProvider.overrideWithValue(beam),
        multicastLeaseProvider.overrideWithValue(FakeMulticastLease()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: BeamSheet(files: <BeamFile>[_file])),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('says it is looking before it gives up', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _ScriptedBeam(const <List<BeamTarget>>[]));

    expect(
      find.text('Looking for receivers on your network…'),
      findsOneWidget,
    );
    // Nothing to search again yet — pressing it would restart a search that is
    // already running.
    expect(find.text('Search again'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('offers Search again once the network has gone quiet', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _ScriptedBeam(const <List<BeamTarget>>[]));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No receivers found', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Search again'), findsOneWidget);
  });

  testWidgets('Search again really re-announces, and finds what appeared', (
    WidgetTester tester,
  ) async {
    // The reason this button exists: a receiver is usually switched on *after*
    // the sheet is open, and the announcement is a one-shot shout — a receiver
    // that started listening later never heard anything to answer.
    final _ScriptedBeam beam = _ScriptedBeam(const <List<BeamTarget>>[
      <BeamTarget>[],
      <BeamTarget>[_desktop],
    ]);
    await _pump(tester, beam);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search again'));
    await tester.pumpAndSettle();

    expect(beam.subscriptions, 2);
    expect(find.text('workstation'), findsOneWidget);
  });

  testWidgets('always offers a typed address, even while still looking', (
    WidgetTester tester,
  ) async {
    // A network with client isolation or multicast filtering never answers, and
    // waiting out the timer to be told so is time spent for nothing.
    await _pump(tester, _ScriptedBeam(const <List<BeamTarget>>[]));

    expect(find.text('Enter an address'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('lists a receiver that answers, with its own alias', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _ScriptedBeam(const <List<BeamTarget>>[
        <BeamTarget>[_desktop],
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('workstation'), findsOneWidget);
    expect(find.text('192.168.50.20'), findsOneWidget);
  });
}
