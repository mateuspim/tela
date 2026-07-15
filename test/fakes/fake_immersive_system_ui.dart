import 'package:tela/core/ui/immersive_system_ui.dart';

/// Records immersive system-chrome transitions without a platform channel.
final class FakeImmersiveSystemUi implements ImmersiveSystemUi {
  /// Ordered enter/restore events.
  final List<String> events = <String>[];

  /// Number of immersive entries.
  int get enterCalls => events.where((String event) => event == 'enter').length;

  /// Number of normal-system-UI restorations.
  int get restoreCalls =>
      events.where((String event) => event == 'restore').length;

  @override
  Future<void> enterImmersive() async {
    events.add('enter');
  }

  @override
  Future<void> restoreNormal() async {
    events.add('restore');
  }
}
