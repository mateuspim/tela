import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/use_cases/save_api_key.dart';

/// Whether a Wallhaven API key is stored, and the one way the UI changes that.
final AsyncNotifierProvider<ApiKeyController, bool> apiKeyProvider =
    AsyncNotifierProvider<ApiKeyController, bool>(ApiKeyController.new);

/// Holds *whether* a key exists — never the key.
///
/// The secret is read only inside the network interceptor, so the widget layer
/// has nothing to leak into a rebuild, a snackbar, or a crash report.
class ApiKeyController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(secretStoreProvider).hasApiKey();

  /// Saves [apiKey] and reports whether Wallhaven confirmed it.
  ///
  /// Rethrows the `InvalidApiKeyFailure` of a rejected key. The use case has
  /// already put any previous key back by then, so this state is left untouched
  /// and the caller only has to say so.
  Future<ApiKeySaveOutcome> save(String apiKey) async {
    final ApiKeySaveOutcome outcome = await ref.read(saveApiKeyProvider)(
      apiKey,
    );
    state = const AsyncData<bool>(true);
    return outcome;
  }

  /// Deletes the key, re-locking explicit content.
  Future<void> forget() async {
    await ref.read(forgetApiKeyProvider)();
    state = const AsyncData<bool>(false);
  }
}
