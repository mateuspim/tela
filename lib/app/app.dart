import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/router.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// The root widget.
class TelaApp extends StatefulWidget {
  /// Creates the app.
  const TelaApp({super.key});

  @override
  State<TelaApp> createState() => _TelaAppState();
}

class _TelaAppState extends State<TelaApp> {
  /// Built once: rebuilding a GoRouter drops the navigation stack.
  late final GoRouter _router = TelaRouter.create();

  /// Reads the Material You palette, then themes the app with it.
  ///
  /// Both schemes arrive null on Android 11 and below, where Monet does not
  /// exist; [TelaTheme] falls back to its seed, so this builder is the only
  /// place that has to know Monet is optional.
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDevice, ColorScheme? darkDevice) =>
          MaterialApp.router(
            onGenerateTitle: (BuildContext context) =>
                AppLocalizations.of(context).appTitle,
            routerConfig: _router,
            theme: TelaTheme.light(lightDevice),
            darkTheme: TelaTheme.dark(darkDevice),
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
    );
  }
}
