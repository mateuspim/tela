import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/build_edition.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/app/router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/app/wallpaper_sources.dart';
import 'package:tela/data/secrets/unavailable_secret_store.dart';
import 'package:tela/domain/models/purity.dart';
import 'package:tela/domain/ports/secret_store.dart';
import 'package:tela/domain/ports/wallpaper_source.dart';

void main() {
  test('compiled clean edition has only its allowed runtime capabilities', () {
    if (buildEdition.allowsExplicitContent) return;
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final List<WallpaperSource> sources = container.read(
      wallpaperSourcesProvider,
    );
    final SecretStore secrets = container.read(secretStoreProvider);

    expect(secrets, isA<UnavailableSecretStore>());
    expect(sources.first.capabilities.purities, isNot(contains(Purity.nsfw)));
    expect(
      sources.length,
      buildEdition.includesKonachan ? 2 : 1,
    );
    for (final WallpaperSource source in sources) {
      expect(source.capabilities.purities, isNot(contains(Purity.nsfw)));
    }
  });

  // Regression for device pass F8 (2026-10-03): Safe offered the private tier
  // as a download destination while compiling out the only screen that opens
  // it, so what was sent there became unreachable. CI runs this per edition.
  test('every edition registers the private library routes', () {
    final GoRouter router = TelaRouter.create();
    addTearDown(router.dispose);

    expect(
      router.namedLocation(TelaRoutes.privateLibraryName),
      TelaRoutes.privateLibraryPath,
    );
    expect(
      router.namedLocation(TelaRoutes.privateViewerName),
      TelaRoutes.privateViewerPath,
    );
  });
}
