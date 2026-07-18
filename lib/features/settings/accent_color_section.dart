import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/accent_color.dart';
import 'package:tela/features/settings/accent_color_controller.dart';
import 'package:tela/features/settings/accent_picker_sheet.dart';

/// Picks the brand accent: follow the wallpaper, a curated preset, or any
/// colour at all.
///
/// The whole set is one radio — follow-wallpaper included — because "no fixed
/// accent" is a choice like any other, not the absence of one.
class AccentColorSection extends ConsumerWidget {
  /// Creates the accent picker section.
  const AccentColorSection({super.key});

  /// A small, spectrum-spread palette of brand-weight colours. Muted-rich on
  /// purpose: an accent this app shows sparingly still has to sit under a wall
  /// of photos without shouting over them.
  static const List<Color> presets = <Color>[
    Color(0xFF2C63E0), // cobalt
    Color(0xFF1F8F8A), // teal
    Color(0xFF3E8E43), // green
    Color(0xFFCF5A18), // burnt orange
    Color(0xFFC6413B), // red
    Color(0xFFB5407E), // magenta
    Color(0xFF655CD6), // violet
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AccentColor? accent = ref.watch(accentColorProvider).value;
    final Color? custom = _customColor(accent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.settingsAccentTitle, style: _labelStyle(context)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _followSwatch(context, ref, selected: accent == null),
              for (final Color color in presets)
                _presetSwatch(context, ref, color, accent),
              _customSwatch(context, ref, custom),
            ],
          ),
        ],
      ),
    );
  }

  /// The custom colour to show as selected: a saved accent that is none of the
  /// presets. A preset or follow-wallpaper leaves the custom slot un-filled.
  Color? _customColor(AccentColor? accent) {
    if (accent == null) return null;
    final bool isPreset = presets.any((Color c) => _rgb(c) == accent.rgb);
    return isPreset ? null : Color(0xFF000000 | accent.rgb);
  }

  Widget _followSwatch(
    BuildContext context,
    WidgetRef ref, {
    required bool selected,
  }) {
    return _AccentSwatch(
      selected: selected,
      semanticLabel: AppLocalizations.of(context).settingsAccentFollowSystem,
      onTap: () => ref.read(accentColorProvider.notifier).followSystem(),
      background: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.auto_awesome_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _presetSwatch(
    BuildContext context,
    WidgetRef ref,
    Color color,
    AccentColor? accent,
  ) {
    final AccentColor value = AccentColor(_rgb(color));
    return _AccentSwatch(
      selected: accent == value,
      background: color,
      semanticLabel: AppLocalizations.of(
        context,
      ).settingsAccentSwatchLabel(value.hex),
      onTap: () => ref.read(accentColorProvider.notifier).choose(value),
    );
  }

  Widget _customSwatch(BuildContext context, WidgetRef ref, Color? custom) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _AccentSwatch(
      selected: custom != null,
      background: custom ?? scheme.surfaceContainerHighest,
      semanticLabel: AppLocalizations.of(context).settingsAccentCustom,
      onTap: () => _pickCustom(context, ref, custom),
      child: Icon(
        custom == null ? Icons.colorize_outlined : Icons.edit_outlined,
        size: 18,
        color: custom == null
            ? scheme.onSurfaceVariant
            : _onColor(custom, scheme),
      ),
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    WidgetRef ref,
    Color? current,
  ) async {
    final Color? picked = await AccentPickerSheet.show(
      context,
      initial: current ?? presets.first,
    );
    if (picked == null) return;
    await ref
        .read(accentColorProvider.notifier)
        .choose(AccentColor(_rgb(picked)));
  }

  /// Readable ink for an icon sitting on [color].
  Color _onColor(Color color, ColorScheme scheme) =>
      color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  TextStyle? _labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleSmall
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  static int _rgb(Color color) => color.toARGB32() & 0xFFFFFF;
}

/// One tappable swatch: a filled circle that grows a ring when selected.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.selected,
    required this.background,
    required this.semanticLabel,
    required this.onTap,
    this.child,
  });

  final bool selected;
  final Color background;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget? child;

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkResponse(
        onTap: onTap,
        radius: _size * 0.7,
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Center(child: child ?? _check(scheme)),
        ),
      ),
    );
  }

  /// A tick only when selected and the swatch has no icon of its own.
  Widget _check(ColorScheme scheme) {
    if (!selected) return const SizedBox.shrink();
    final bool light = background.computeLuminance() > 0.5;
    return Icon(
      Icons.check,
      size: 20,
      color: light ? Colors.black87 : Colors.white,
    );
  }
}
