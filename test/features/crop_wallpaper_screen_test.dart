import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/models/resolution.dart';
import 'package:tela/domain/models/wallpaper.dart';
import 'package:tela/domain/models/wallpaper_apply_failure.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/features/detail/crop_wallpaper_screen.dart';

import '../fakes/fake_wallpaper_applier.dart';

void main() {
  testWidgets('Set frames the wallpaper and applies a bounded region', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    final Wallpaper wallpaper = _wallpaper(Purity.sfw);
    await _openCropEditor(tester, wallpaper, applier);

    await tester.tap(find.byKey(CropWallpaperScreen.setButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home screen'));
    await tester.pumpAndSettle();

    expect(applier.receivedSource, Uri.parse(wallpaper.fullImageUrl));
    expect(applier.receivedTarget, WallpaperTarget.home);
    final CropRegionMatch region = _region(applier);
    expect(region.right, lessThanOrEqualTo(wallpaper.resolution.width));
    expect(region.bottom, lessThanOrEqualTo(wallpaper.resolution.height));
    expect(find.text('Wallpaper set.'), findsOneWidget);
    expect(find.byType(CropWallpaperScreen), findsNothing);
  });

  testWidgets('the editor sets an explicit wallpaper — pixels stay in app', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier();
    await _openCropEditor(tester, _wallpaper(Purity.nsfw), applier);

    await tester.tap(find.byKey(CropWallpaperScreen.setButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home and lock screens'));
    await tester.pumpAndSettle();

    expect(applier.receivedTarget, WallpaperTarget.both);
    expect(applier.callCount, 1);
  });

  testWidgets('zooming transforms the decoded layer without re-decoding it', (
    WidgetTester tester,
  ) async {
    // Regression: the layer used to be sized to image*scale, so every pinch
    // frame re-decoded at a new size and flashed the black placeholder. It is
    // now decoded once at cover scale; zoom is a paint-time Transform. So its
    // layout size must not change under a pinch, while its on-screen rect does.
    await _openCropEditor(
      tester,
      _wallpaper(Purity.sfw),
      FakeWallpaperApplier(),
    );
    final Finder layer = find.byKey(CropWallpaperScreen.imageLayerKey);
    final Size sizeBefore = tester.getSize(layer);
    final double widthBefore = tester.getRect(layer).width;

    final Offset center = tester.getCenter(layer);
    final TestGesture a = await tester.createGesture(pointer: 1);
    final TestGesture b = await tester.createGesture(pointer: 2);
    await a.down(center - const Offset(20, 0));
    await b.down(center + const Offset(20, 0));
    await tester.pump();
    await a.moveTo(center - const Offset(120, 0));
    await b.moveTo(center + const Offset(120, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();

    expect(tester.getSize(layer), sizeBefore);
    expect(tester.getRect(layer).width, greaterThan(widthBefore));
  });

  testWidgets('a failed apply reports and keeps the editor open', (
    WidgetTester tester,
  ) async {
    final FakeWallpaperApplier applier = FakeWallpaperApplier(
      failure: const WallpaperApplyFailure(WallpaperApplyProblem.rejected),
    );
    await _openCropEditor(tester, _wallpaper(Purity.sfw), applier);

    await tester.tap(find.byKey(CropWallpaperScreen.setButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock screen'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't set this wallpaper."), findsOneWidget);
    expect(find.byType(CropWallpaperScreen), findsOneWidget);
  });
}

typedef CropRegionMatch = ({int right, int bottom});

CropRegionMatch _region(FakeWallpaperApplier applier) {
  final region = applier.receivedRegion!;
  return (right: region.right, bottom: region.bottom);
}

/// Pushes the editor over a host route, so its self-pop on success lands back
/// on a real route rather than trying to pop the last one.
Future<void> _openCropEditor(
  WidgetTester tester,
  Wallpaper wallpaper,
  FakeWallpaperApplier applier,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        wallpaperApplierProvider.overrideWithValue(applier),
      ],
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Host(wallpaper: wallpaper),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(CropWallpaperScreen), findsOneWidget);
}

class _Host extends StatelessWidget {
  const _Host({required this.wallpaper});

  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  CropWallpaperScreen(wallpaper: wallpaper),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Wallpaper _wallpaper(Purity purity) => Wallpaper(
  id: 'e7jvjd',
  fullImageUrl: 'https://w.wallhaven.cc/full/e7/wallhaven-e7jvjd.jpg',
  thumbSmallUrl: 'https://th.wallhaven.cc/small/e7/e7jvjd.jpg',
  thumbLargeUrl: 'https://th.wallhaven.cc/lg/e7/e7jvjd.jpg',
  thumbOriginalUrl: 'https://th.wallhaven.cc/orig/e7/e7jvjd.jpg',
  resolution: const Resolution(3840, 2160),
  fileSizeBytes: 1048576,
  purity: purity,
  category: Category.general,
  colors: const <String>['#660000'],
);
