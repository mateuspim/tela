import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tela/app/build_edition.dart';
import 'package:tela/app/providers.dart';
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
}
