import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/download_destination_choice.dart';
import 'package:tela/core/ui/download_destination_dialog.dart';
import 'package:tela/domain/models/download_destination_streak.dart';
import 'package:tela/domain/models/download_folder.dart';
import 'package:tela/domain/models/download_location.dart';
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

    // Regression, owner 2026-10-16: with downloads set to the SD card, picking
    // "Private library" kept landing explicit wallpapers on the device, and
    // nothing on the card said that tier never follows the card.
    testWidgets('names the disk each destination writes to', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.nsfw, location: _onSdCard);

      expect(find.text('Saves to SD card'), findsOneWidget);
      expect(find.text('Saves to Internal storage'), findsOneWidget);
    });

    testWidgets('names no disk when the location is unknown', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.nsfw);
      expect(find.textContaining('Saves to'), findsNothing);
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

      final Finder makeDefault = find.text('Make this the default for Sketchy');
      await tester.ensureVisible(makeDefault);
      await tester.tap(makeDefault);
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
      expect(find.textContaining('the default for'), findsNothing);
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

      expect(find.textContaining('the default for'), findsNothing);
    });

    // The one gated corner: making explicit downloads default to files can tip
    // them onto a removable card, whose warning lives in Settings. The chooser
    // still saves there for one download; it just does not offer permanence.
    testWidgets('withholds the offer for explicit files-outside-gallery', (
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
      expect(find.textContaining('the default for'), findsNothing);
    });

    // Two promises were reading as one, both wearing the pin (K flag #3). The
    // pin outranks the per-purity default, so an offer to change that default
    // while a pin is in force promises something the user cannot see until they
    // Stop — the run is still worth marking, the offer is not.
    testWidgets('stands down while a pin is in force', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        purity: Purity.sketchy,
        pinnedTier: StorageTier.sharedGallery,
        streak: DownloadDestinationStreak(
          tier: StorageTier.appPrivate,
          length: 4,
        ),
      );

      expect(find.text('Last 4 saved here'), findsOneWidget);
      expect(find.textContaining('the default for'), findsNothing);
    });

    // The pin icon and the pin's words belong to "Keep sending here" alone.
    testWidgets('never wears the pin icon', (WidgetTester tester) async {
      await _open(
        tester,
        purity: Purity.sketchy,
        streak: DownloadDestinationStreak(
          tier: StorageTier.appPrivate,
          length: 3,
        ),
      );

      expect(find.text('Make this the default for Sketchy'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      expect(find.byIcon(Icons.push_pin), findsNothing);
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

      // Scrolled to first: the tag row made the dialog taller than a phone's
      // dialog area, so its content genuinely scrolls now. The destinations are
      // still above the fold — it is the switches below them that move.
      await tester.ensureVisible(find.text('Keep sending here'));
      await tester.tap(find.text('Keep sending here'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Private library'));
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
    // Regression for device pass F3 (2026-10-03): on the SM-X730 in landscape
    // the stacked chooser overran the height and cut this subtitle mid-line.
    testWidgets('fits a landscape tablet without cutting the last switch', (
      WidgetTester tester,
    ) async {
      _viewport(tester, const Size(2560, 1600), pixelRatio: 2);
      await _openBatch(tester, purities: <Purity>{Purity.sfw}, count: 19714);

      expect(
        find.byKey(const Key('download-destination-columns')),
        findsOneWidget,
      );
      final Rect subtitle = tester.getRect(
        find.text('Every download goes straight here until you change it.'),
      );
      final Rect visible = tester.getRect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(subtitle.bottom, lessThanOrEqualTo(visible.bottom));
    });

    testWidgets('stacks on a portrait phone', (WidgetTester tester) async {
      _viewport(tester, const Size(1080, 2400), pixelRatio: 2.75);
      await _open(tester, purity: Purity.sfw);

      expect(
        find.byKey(const Key('download-destination-columns')),
        findsNothing,
      );
    });

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

    // The heading is the only thing that says how far one tap reaches: the
    // cards below name destinations, not quantities. A bare "Download to" over
    // nine wallpapers reads like a single download (K flag #2).
    testWidgets('names how many wallpapers the answer governs', (
      WidgetTester tester,
    ) async {
      await _openBatch(tester, purities: <Purity>{Purity.sketchy}, count: 9);

      expect(find.text('Download 9 wallpapers to'), findsOneWidget);
      expect(find.text('Download to'), findsNothing);
    });

    testWidgets('counts one wallpaper singly', (WidgetTester tester) async {
      await _openBatch(tester, purities: <Purity>{Purity.sketchy}, count: 1);

      expect(find.text('Download 1 wallpaper to'), findsOneWidget);
    });

    // The single chooser keeps its bare heading — the wallpaper being placed is
    // the one already on screen, so a count would be noise.
    testWidgets('the single chooser carries no count', (
      WidgetTester tester,
    ) async {
      await _open(tester, purity: Purity.sketchy);

      expect(find.text('Download to'), findsOneWidget);
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
  DownloadLocation? location,
}) async {
  final BuildContext context = await _host(tester);
  final Future<DownloadDestinationChoice?> picked = chooseDownloadDestination(
    context,
    purity: purity,
    configuredTier: configuredTier,
    streak: streak,
    pinnedTier: pinnedTier,
    location: location,
  );
  await tester.pumpAndSettle();
  return picked;
}

/// The batch twin of [_open].
Future<Future<DownloadDestinationChoice?>> _openBatch(
  WidgetTester tester, {
  required Set<Purity> purities,
  int count = 2,
  StorageTier? pinnedTier,
}) async {
  final BuildContext context = await _host(tester);
  final Future<DownloadDestinationChoice?> picked =
      chooseBatchDownloadDestination(
        context,
        purities: purities,
        count: count,
        pinnedTier: pinnedTier,
      );
  await tester.pumpAndSettle();
  return picked;
}

/// Explicit downloads set to a folder on a mounted SD card.
const DownloadLocation _onSdCard = DownloadLocation(
  folder: null,
  explicitFolder: DownloadFolder(
    volumeLabel: 'SD card',
    relativePath: 'Pictures/.tela',
    isRemovable: true,
    isAvailable: true,
  ),
  sdCardAvailable: true,
);

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

/// Sizes the test window like a real device, undone after the test.
void _viewport(
  WidgetTester tester,
  Size physical, {
  required double pixelRatio,
}) {
  tester.view
    ..physicalSize = physical
    ..devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}
