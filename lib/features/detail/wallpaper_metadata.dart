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
    required this.onBlockTag,
    super.key,
  });

  /// Detail data to render.
  final WallpaperDetails details;

  /// Called with the tag or uploader the user tapped.
  ///
  /// The panel does not navigate itself: the screen it sits on owns the routes,
  /// and a callback is what lets this widget be tested without one.
  final ValueChanged<WallpaperLink> onFollow;

  /// Called with the tag the user long-pressed, asking to hide it everywhere.
  ///
  /// Same reasoning as [onFollow]: the confirmation dialog and the blocklist
  /// write both belong to the screen, not to this presentational panel.
  final ValueChanged<WallpaperTag> onBlockTag;

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
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                _summaryGrid(context, l10n, item, constraints.maxWidth),
          ),
          const SizedBox(height: 16),
          _MetadataRow(l10n.detailFileType, item.fileType),
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
          _Colors(colors: item.wallpaper.colors, onFollow: onFollow),
          const SizedBox(height: 16),
          Text(l10n.detailTags, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _Tags(tags: item.tags, onFollow: onFollow, onBlock: onBlockTag),
        ],
      ),
    );
  }

  Widget _summaryGrid(
    BuildContext context,
    AppLocalizations l10n,
    WallpaperDetails item,
    double width,
  ) {
    final double tileWidth = (width - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _MetadataTile(
          width: tileWidth,
          label: l10n.detailResolution,
          value: item.wallpaper.resolution.toString(),
        ),
        _MetadataTile(
          width: tileWidth,
          label: l10n.detailFileSize,
          value: _bytes(l10n, item.wallpaper.fileSizeBytes),
        ),
        _MetadataTile(
          width: tileWidth,
          label: l10n.detailCategory,
          value: categoryLabel(l10n, item.wallpaper.category),
        ),
        _MetadataTile(
          width: tileWidth,
          label: l10n.detailPurity,
          value: purityLabel(l10n, item.wallpaper.purity),
        ),
      ],
    );
  }

  String _bytes(AppLocalizations l10n, int bytes) =>
      l10n.detailFileSizeBytes(_number(bytes));

  String _number(int value) => NumberFormat.decimalPattern().format(value);
}

/// A glanceable fact at the top of the metadata panel.
class _MetadataTile extends StatelessWidget {
  const _MetadataTile({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
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

/// Dominant palette chips, each opening that colour's listing.
///
/// A colour Wallhaven sends in a shape we don't recognise is dropped rather
/// than painted: it costs that one swatch, where parsing it eagerly would take
/// the whole metadata panel down with it. The readable ones are tappable —
/// "more wallpapers in this colour", under whatever filters the user is on —
/// the same follow the tags and uploader offer.
class _Colors extends StatelessWidget {
  const _Colors({required this.colors, required this.onFollow});

  final List<String> colors;
  final ValueChanged<WallpaperLink> onFollow;

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
          WallpaperSwatch(
            color: color,
            onTap: () => onFollow(ColorLink(color)),
          ),
      ],
    );
  }
}

/// A wrapping list of tag chips, or a localized absence state.
///
/// [ActionChip], not [Chip]: each one opens that tag's listing, and a chip that
/// does nothing is indistinguishable from one that does until you press it. A
/// long press is layered on top for [onBlock] rather than given its own
/// affordance — chips are already dense here, and "hide this everywhere" is
/// exactly the kind of held-down, slightly out-of-the-way gesture that guards
/// against a stray tap doing it by accident.
class _Tags extends StatelessWidget {
  const _Tags({
    required this.tags,
    required this.onFollow,
    required this.onBlock,
  });

  final List<WallpaperTag> tags;
  final ValueChanged<WallpaperLink> onFollow;
  final ValueChanged<WallpaperTag> onBlock;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text(AppLocalizations.of(context).detailNotProvided);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[for (final WallpaperTag tag in tags) _tagChip(tag)],
    );
  }

  Widget _tagChip(WallpaperTag tag) {
    return GestureDetector(
      onLongPress: () => onBlock(tag),
      child: ActionChip(
        label: Text(tag.name),
        onPressed: () => onFollow(TagLink(tag)),
      ),
    );
  }
}
