import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/storage_tier.dart';

void main() {
  group('chooseDownloadDestination', () {
    // The point of the redesign: it is centred, not at the bottom edge. Pinned
    // structurally because "it looks centred" is not something a test can see.
    testWidgets('is a dialog, not a bottom sheet', (WidgetTester tester) async {
      await _open(tester, purity: Purity.sfw);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('offers every destination with what it means', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.sfw);

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
      await _open(tester, purity: Purity.nsfw);

      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.text('Private library'), findsOneWidget);
    });

    testWidgets('names the purity when there is something to warn about', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.sketchy);
      expect(find.text('Sketchy'), findsOneWidget);
    });

    testWidgets('stays quiet for a safe wallpaper', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.sfw);
      expect(find.text('Safe'), findsNothing);
    });

    testWidgets('resolves to the destination that was tapped', (
      WidgetTester tester,
    ) async {
      final Future<DownloadDestinationChoice?> picked = await _open(
        tester,
        purity: Purity.sfw,
      );

      await tester.tap(find.text('Private library'));
      await tester.pumpAndSettle();

      final DownloadDestinationChoice? choice = await picked;
      expect(choice?.tier, StorageTier.appPrivate);
      expect(choice?.remember, isFalse);
    });

    testWidgets('resolves to null when cancelled', (
      WidgetTester tester,
    ) async {
      final Future<DownloadDestinationChoice?> picked = await _open(
        tester,
        purity: Purity.sfw,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await picked, isNull);
    });
  });

  group('the streak suggestion', () {
    testWidgets('offers to make a diverging run the default', (
      WidgetTester tester,
    ) async {
      final Future<DownloadDestinationChoice?> picked = await _open(
        tester,
        purity: Purity.sketchy,
        streak: DownloadDestinationStreak(
          tier: StorageTier.appPrivate,
          length: 3,
        ),
      );

      expect(find.text('Last 3 saved here'), findsOneWidget);

      final Finder always = find.text('Always save Sketchy here');
      await tester.ensureVisible(always);
      await tester.tap(always);
      await tester.pumpAndSettle();

      final DownloadDestinationChoice? choice = await picked;
      expect(choice?.tier, StorageTier.appPrivate);
      expect(choice?.remember, isTrue);
    });

    testWidgets('says nothing until the run is long enough', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        purity: Purity.sfw,
        streak: DownloadDestinationStreak(
          tier: StorageTier.appPrivate,
          length: 2,
        ),
      );

      expect(find.textContaining('Last'), findsNothing);
      expect(find.textContaining('Always'), findsNothing);
    });

    // A run that merely agrees with where a tap already goes is nothing to
    // suggest — there is no default to change.
    testWidgets('says nothing when the run is already the default', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        purity: Purity.sfw,
        configuredTier: StorageTier.appPrivate,
        streak: DownloadDestinationStreak(
          tier: StorageTier.appPrivate,
          length: 5,
        ),
      );

      expect(find.textContaining('Always'), findsNothing);
    });

    // The one gated corner: making explicit downloads default to files can tip
    // them onto a removable card, whose warning lives in Settings. The chooser
    // still saves there for one download; it just does not offer permanence.
    testWidgets('withholds "Always" for explicit files-outside-gallery', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        purity: Purity.nsfw,
        configuredTier: StorageTier.appPrivate,
        streak: DownloadDestinationStreak(
          tier: StorageTier.filesOutsideGallery,
          length: 4,
        ),
      );

      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.textContaining('Always'), findsNothing);
    });
  });

  group('the "Keep sending here" pin', () {
    testWidgets('pins the tapped tier when the switch is on', (
      WidgetTester tester,
    ) async {
      final Future<DownloadDestinationChoice?> picked = await _open(
        tester,
        purity: Purity.sfw,
      );

      await tester.tap(find.text('Keep sending here'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Private library'));
      await tester.pumpAndSettle();

      final DownloadDestinationChoice? choice = await picked;
      expect(choice?.tier, StorageTier.appPrivate);
      expect(choice?.pin, isTrue);
    });

    testWidgets('leaves a plain tap unpinned when the switch is off', (
      WidgetTester tester,
    ) async {
      final Future<DownloadDestinationChoice?> picked = await _open(
        tester,
        purity: Purity.sfw,
      );

      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();

      final DownloadDestinationChoice? choice = await picked;
      expect(choice?.pin, isFalse);
      expect(choice?.stopsPin, isFalse);
    });

    testWidgets('shows an active pin and offers to stop it', (
      WidgetTester tester,
    ) async {
      final Future<DownloadDestinationChoice?> picked = await _open(
        tester,
        purity: Purity.sfw,
        pinnedTier: StorageTier.appPrivate,
      );

      expect(
        find.text('Sending every download to Private library.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      final DownloadDestinationChoice? choice = await picked;
      expect(choice?.stopsPin, isTrue);
      expect(choice?.tier, isNull);
    });

    // With no pin in force there is nothing to stop, so the way out is Cancel.
    testWidgets('offers no Stop when no pin is set', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.sfw);
      expect(find.text('Stop'), findsNothing);
    });
  });

  group('chooseBatchDownloadDestination', () {
    testWidgets('offers every tier when the batch is all safe', (
      WidgetTester tester,
    ) async {
      await _openBatch(tester, purities: <Purity>{Purity.sfw, Purity.sketchy});

      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.text('Private library'), findsOneWidget);
    });

    // The intersection: one explicit wallpaper in the set takes the gallery off
    // the table for the whole batch, so one destination can hold all of them.
    testWidgets('drops the gallery when any wallpaper is explicit', (
      WidgetTester tester,
    ) async {
      await _openBatch(tester, purities: <Purity>{Purity.sfw, Purity.nsfw});

      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Files, not gallery'), findsOneWidget);
      expect(find.text('Private library'), findsOneWidget);
    });

    // A bulk action is not a per-item habit, so the streak's "Always" never
    // appears — but the pin toggle does, since pinning is a "put everything
    // here" decision.
    testWidgets('has the pin toggle but never an "Always"', (
      WidgetTester tester,
    ) async {
      await _openBatch(tester, purities: <Purity>{Purity.sfw});

      expect(find.text('Keep sending here'), findsOneWidget);
      expect(find.textContaining('Always'), findsNothing);
    });
  });
}

/// Pumps a host app and opens the dialog from a real context, returning the
/// pending pick. Called outside any tester-driven tap so the dialog's future is
/// not orphaned inside flutter_test's guarded zone — same reason as the volume
/// sheet's own harness.
Future<Future<DownloadDestinationChoice?>> _open(
  WidgetTester tester, {
  required Purity purity,
  StorageTier configuredTier = StorageTier.sharedGallery,
  DownloadDestinationStreak? streak,
  StorageTier? pinnedTier,
}) async {
  final BuildContext context = await _host(tester);
  final Future<DownloadDestinationChoice?> picked = chooseDownloadDestination(
    context,
    purity: purity,
    configuredTier: configuredTier,
    streak: streak,
    pinnedTier: pinnedTier,
  );
  await tester.pumpAndSettle();
  return picked;
}

/// The batch twin of [_open].
Future<Future<DownloadDestinationChoice?>> _openBatch(
  WidgetTester tester, {
  required Set<Purity> purities,
  StorageTier? pinnedTier,
}) async {
  final BuildContext context = await _host(tester);
  final Future<DownloadDestinationChoice?> picked =
      chooseBatchDownloadDestination(
        context,
        purities: purities,
        pinnedTier: pinnedTier,
      );
  await tester.pumpAndSettle();
  return picked;
}

/// Pumps the localized host app and hands back a real context to open from.
Future<BuildContext> _host(WidgetTester tester) async {
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
  return tester.element(find.byType(Scaffold));
}
