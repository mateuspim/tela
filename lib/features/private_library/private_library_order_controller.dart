import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/domain/models/library_order.dart';
import 'package:tela/domain/ports/settings_repository.dart';

/// Which way the private library lists its images, remembered across visits.
final AsyncNotifierProvider<PrivateLibraryOrderController, LibraryOrder>
privateLibraryOrderProvider =
    AsyncNotifierProvider<PrivateLibraryOrderController, LibraryOrder>(
      PrivateLibraryOrderController.new,
    );

/// Loads the order and writes a change straight back through the port, the
/// same no-save-button rule `TileDensityController` follows.
///
/// ```dart
/// ref.read(privateLibraryOrderProvider.notifier).choose(order);
/// ```
class PrivateLibraryOrderController extends AsyncNotifier<LibraryOrder> {
  @override
  Future<LibraryOrder> build() {
    return ref.watch(settingsRepositoryProvider).loadPrivateLibraryOrder();
  }

  /// Lists the private library in [order] from now on.
  Future<void> choose(LibraryOrder order) async {
    if (state.value == order) return;
    // Persisted before shown, so the screen never claims an order that a
    // restart would forget.
    final SettingsRepository settings = ref.read(settingsRepositoryProvider);
    await settings.savePrivateLibraryOrder(order);
    state = AsyncData<LibraryOrder>(order);
  }
}
