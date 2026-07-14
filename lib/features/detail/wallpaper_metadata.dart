import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_swatch.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/wallpaper_color.dart';
import 'package:tela/domain/models/wallpaper_details.dart';
import 'package:tela/domain/models/wallpaper_link.dart';

/// The textual and colour metadata returned only by `/w/{id}`.
class WallpaperMetadata extends StatelessWidget {
  /// Creates metadata for one complete Wallhaven detail response.
  const WallpaperMetadata({
    required this.details,
    required this.onFollow,
    super.key,
  });

  /// Detail data to render.
  final WallpaperDetails details;

  /// Called with the tag or uploader the user tapped.
  ///
  /// The panel does not navigate itself: the screen it sits on owns the routes,
  /// and a callback is what lets this widget be tested without one.
  final ValueChanged<WallpaperLink> onFollow;

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
          _MetadataRow(
            l10n.detailCategory,
            categoryLabel(l10n, item.wallpaper.category),
          ),
          _MetadataRow(
            l10n.detailPurity,
            purityLabel(l10n, item.wallpaper.purity),
          ),
          _MetadataRow(l10n.detailRatio, item.ratio),
          _MetadataRow(l10n.detailViews, _number(item.views)),
          _MetadataRow(l10n.detailFavorites, _number(item.favorites)),
          _MetadataRow.linked(
            l10n.detailUploader,
            value: _MetadataLink(
              text: item.uploader.username,
              onTap: () => onFollow(UploaderLink(item.uploader.username)),
            ),
          ),
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
          _Tags(tags: item.tags, onFollow: onFollow),
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
  /// A plain value, selectable so it can be copied out.
  _MetadataRow(this.label, String text)
    : value = SelectableText(text),
      align = CrossAxisAlignment.start;

  /// A value that leads somewhere. Takes the widget rather than a second copy
  /// of the column layout, which is what kept the two rows aligned.
  ///
  /// Centred, not top-aligned: a linked value is a button, and its touch target
  /// is taller than a line of text — top-aligning it left the uploader visibly
  /// sitting below its own label (seen on the device, 2026-07-14).
  const _MetadataRow.linked(this.label, {required this.value})
    : align = CrossAxisAlignment.center;

  final String label;
  final Widget value;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: align,
        children: <Widget>[
          SizedBox(width: 112, child: Text(label)),
          Expanded(child: value),
        ],
      ),
    );
  }
}

/// A metadata value you can follow, styled as the link it is.
///
/// A [TextButton] rather than a tapped [Text]: it carries button semantics and
/// a real touch target, and a link only a sighted user with a steady thumb can
/// find is not a link.
class _MetadataLink extends StatelessWidget {
  const _MetadataLink({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        // No horizontal padding: the value must start on the same pixel as
        // every other row's, or the column stops looking like a column.
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
        ),
        child: Text(text),
      ),
    );
  }
}

/// Dominant palette chips, with labels for non-visual access.
///
/// A colour Wallhaven sends in a shape we don't recognise is dropped rather
/// than painted: it costs that one swatch, where parsing it eagerly would take
/// the whole metadata panel down with it.
class _Colors extends StatelessWidget {
  const _Colors({required this.colors});

  final List<String> colors;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<WallpaperColor> readable = WallpaperColor.readAll(colors);
    if (readable.isEmpty) {
      return Text(l10n.detailNotProvided);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final WallpaperColor color in readable)
          WallpaperSwatch(color: color),
      ],
    );
  }
}

/// A wrapping list of tag chips, or a localized absence state.
///
/// [ActionChip], not [Chip]: each one opens that tag's listing, and a chip that
/// does nothing is indistinguishable from one that does until you press it.
class _Tags extends StatelessWidget {
  const _Tags({required this.tags, required this.onFollow});

  final List<WallpaperTag> tags;
  final ValueChanged<WallpaperLink> onFollow;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text(AppLocalizations.of(context).detailNotProvided);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final WallpaperTag tag in tags)
          ActionChip(
            label: Text(tag.name),
            onPressed: () => onFollow(TagLink(tag)),
          ),
      ],
    );
  }
}
