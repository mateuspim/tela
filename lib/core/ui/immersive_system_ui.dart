import 'package:flutter/services.dart';

/// The system-chrome lifecycle required by an immersive gallery surface.
abstract interface class ImmersiveSystemUi {
  /// Hides Android system chrome using an immersive mode.
  Future<void> enterImmersive();

  /// Restores tela's normal edge-to-edge system chrome.
  Future<void> restoreNormal();
}

/// Applies immersive system UI through Flutter's platform services.
final class FlutterImmersiveSystemUi implements ImmersiveSystemUi {
  /// Creates the default system-UI adapter.
  const FlutterImmersiveSystemUi();

  @override
  Future<void> enterImmersive() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } on MissingPluginException {
      // Desktop/widget hosts do not provide Android's system-chrome channel.
    } on PlatformException {
      // A missing/old platform implementation must not make the image unusable.
    }
  }

  @override
  Future<void> restoreNormal() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } on MissingPluginException {
      // Desktop/widget hosts do not provide Android's system-chrome channel.
    } on PlatformException {
      // Route exit remains available even when an OEM rejects a chrome update.
    }
  }
}
