import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/router.dart';
import 'package:tela/app/theme.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/features/settings/accent_color_controller.dart';

/// The root widget.
class TelaApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const TelaApp({super.key});

  @override
  ConsumerState<TelaApp> createState() => _TelaAppState();
}

class _TelaAppState extends ConsumerState<TelaApp> {
  /// Built once: rebuilding a GoRouter drops the navigation stack.
  late final GoRouter _router = TelaRouter.create();

  /// Reads the Material You palette and the chosen accent, then themes the app.
  ///
  /// Both device schemes arrive null on Android 11 and below, where Monet does
  /// not exist; [TelaTheme] falls back to its seed, so this builder is the only
  /// place that has to know Monet is optional. The accent is null until its
  /// local read returns — which is simply "follow the palette", so the first
  /// frame is already correct and only sharpens if a fixed accent was saved.
  @override
  Widget build(BuildContext context) {
    final Color? accent = _accentColor(ref.watch(accentColorProvider));
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDevice, ColorScheme? darkDevice) =>
          MaterialApp.router(
            // Flutter stamps a red "DEBUG" ribbon on every debug build; a
            // wallpaper browser is judged on the wall, so keep the corner clean
            // in every build. Release never draws it anyway.
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (BuildContext context) =>
                AppLocalizations.of(context).appTitle,
            routerConfig: _router,
            theme: TelaTheme.light(lightDevice, accent: accent),
            darkTheme: TelaTheme.dark(darkDevice, accent: accent),
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

  /// The opaque [Color] for [accent], or null to follow the device palette —
  /// which covers a still-loading read too, tela's shipped default.
  Color? _accentColor(AsyncValue<AccentColor?> accent) {
    final AccentColor? value = accent.value;
    if (value == null) return null;
    return Color(0xFF000000 | value.rgb);
  }
}
