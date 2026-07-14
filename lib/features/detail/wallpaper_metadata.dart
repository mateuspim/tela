import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/wallpaper_details.dart';

/// The textual and colour metadata returned only by `/w/{id}`.
class WallpaperMetadata extends StatelessWidget {
  /// Creates metadata for one complete Wallhaven detail response.
  const WallpaperMetadata({required this.details, super.key});

  /// Detail data to render.
  final WallpaperDetails details;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final WallpaperDetails item = details;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.detailMetadataTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _MetadataRow(
            l10n.detailResolution,
            item.wallpaper.resolution.toString(),
          ),
          _MetadataRow(
            l10n.detailFileSize,
            _bytes(l10n, item.wallpaper.fileSizeBytes),
          ),
          _MetadataRow(l10n.detailFileType, item.fileType),
          _MetadataRow(l10n.detailCategory, item.wallpaper.category.name),
          _MetadataRow(l10n.detailPurity, item.wallpaper.purity.name),
          _MetadataRow(l10n.detailRatio, item.ratio),
          _MetadataRow(l10n.detailViews, _number(item.views)),
          _MetadataRow(l10n.detailFavorites, _number(item.favorites)),
          _MetadataRow(l10n.detailUploader, item.uploader.username),
          _MetadataRow(
            l10n.detailSource,
            item.source.isEmpty ? l10n.detailNotProvided : item.source,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.detailColors,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _Colors(colors: item.wallpaper.colors),
          const SizedBox(height: 16),
          Text(l10n.detailTags, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _Tags(tags: item.tags),
        ],
      ),
    );
  }

  String _bytes(AppLocalizations l10n, int bytes) =>
      l10n.detailFileSizeBytes(_number(bytes));

  String _number(int value) => NumberFormat.decimalPattern().format(value);
}

/// One two-column metadata value, aligned with the rest of the detail screen.
class _MetadataRow extends StatelessWidget {
  const _MetadataRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 112, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Dominant palette chips, with labels for non-visual access.
class _Colors extends StatelessWidget {
  const _Colors({required this.colors});

  final List<String> colors;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (colors.isEmpty) {
      return Text(l10n.detailNotProvided);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((String hex) => _ColorChip(hex: hex)).toList(),
    );
  }
}

/// A single dominant colour in the detail palette.
class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.hex});

  final String hex;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    return Semantics(
      label: AppLocalizations.of(context).detailColorLabel(hex),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

/// A wrapping list of tag chips, or a localized absence state.
class _Tags extends StatelessWidget {
  const _Tags({required this.tags});

  final List<WallpaperTag> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text(AppLocalizations.of(context).detailNotProvided);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .map((WallpaperTag tag) => Chip(label: Text(tag.name)))
          .toList(),
    );
  }
}
