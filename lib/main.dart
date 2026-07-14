import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/app.dart';

/// Entry point. The [ProviderScope] here is the app's one DI root — every port
/// is bound to an adapter in `app/providers.dart`, never reached for globally.
void main() {
  runApp(const ProviderScope(child: TelaApp()));
}
