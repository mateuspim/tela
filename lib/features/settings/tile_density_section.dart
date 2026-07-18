import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/tile_density.dart';
import 'package:tela/features/settings/settings_section_label.dart';
import 'package:tela/features/settings/tile_density_controller.dart';

/// Picks how large the wallpaper shelves draw their tiles.
///
/// A segmented button rather than the accent's swatches: these three are a
/// single ordered scale with names, not a palette, and the segments read out as
/// their names for anyone who cannot judge size from a preview.
class TileDensitySection extends ConsumerWidget {
  /// Creates the tile-density picker section.
  const TileDensitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Until the local read returns, show the density the wall is already
    // drawing at, so the control never contradicts the screen behind it.
    final TileDensity density =
        ref.watch(tileDensityProvider).value ?? TileDensity.medium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsSectionLabel(text: l10n.settingsTileDensityTitle),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<TileDensity>(
              segments: <ButtonSegment<TileDensity>>[
                for (final TileDensity choice in TileDensity.values)
                  ButtonSegment<TileDensity>(
                    value: choice,
                    label: Text(_label(l10n, choice)),
                  ),
              ],
              selected: <TileDensity>{density},
              showSelectedIcon: false,
              onSelectionChanged: (Set<TileDensity> picked) =>
                  ref.read(tileDensityProvider.notifier).choose(picked.single),
            ),
          ),
        ],
      ),
    );
  }

  String _label(AppLocalizations l10n, TileDensity density) {
    return switch (density) {
      TileDensity.small => l10n.settingsTileDensitySmall,
      TileDensity.medium => l10n.settingsTileDensityMedium,
      TileDensity.large => l10n.settingsTileDensityLarge,
    };
  }
}
