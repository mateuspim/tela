import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/wallpaper_swatch.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/category.dart';
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
    required this.onOpenLink,
    super.key,
  });

  /// Detail data to render.
  final WallpaperDetails details;

  /// Called with a URL to open outside tela — the credited source, or the
  /// wallpaper's Wallhaven page. The screen owns the browser hand-off; a
  /// callback keeps this panel testable without one.
  final ValueChanged<Uri> onOpenLink;

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
                _factGrid(l10n, item, constraints.maxWidth),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.detailColors,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _Colors(colors: item.wallpaper.colors, onFollow: onFollow),
          const SizedBox(height: 16),
          ..._attribution(l10n, item),
          const SizedBox(height: 16),
          Text(l10n.detailTags, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _Tags(tags: item.tags, onFollow: onFollow, onBlock: onBlockTag),
        ],
      ),
    );
  }

  /// Every scalar fact about the wallpaper, in one visual language.
  ///
  /// File type, ratio, views and favorites used to be a plain key-value list
  /// below these four, so the panel spoke two languages for one kind of data.
  /// They are all tiles now; the only things left outside the grid are the ones
  /// that are not facts at all — see [_attribution].
  Widget _factGrid(AppLocalizations l10n, WallpaperDetails item, double width) {
    final double tileWidth = (width - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (final (String, String) fact in _facts(l10n, item))
          _MetadataTile(
            // Keyed by label so a test can prove each fact is a *tile*: the
            // panel used to render half of these as plain key-value rows.
            key: Key('metadata-fact-${fact.$1}'),
            width: tileWidth,
            label: fact.$1,
            value: fact.$2,
          ),
      ],
    );
  }

  /// The grid's contents, in reading order: what the file *is* first, then how
  /// it is classified, then what it weighs socially.
  List<(String, String)> _facts(AppLocalizations l10n, WallpaperDetails item) {
    return <(String, String)>[
      (l10n.detailResolution, item.wallpaper.resolution.toString()),
      (l10n.detailFileSize, _bytes(l10n, item.wallpaper.fileSizeBytes)),
      // Omitted rather than filled with a placeholder when the source has no
      // category axis: an empty row would read as "uncategorised", which is a
      // different claim from "this site does not classify that way".
      if (item.wallpaper.category case final Category category)
        (l10n.detailCategory, categoryLabel(l10n, category)),
      (l10n.detailPurity, purityLabel(l10n, item.wallpaper.purity)),
      (l10n.detailFileType, item.fileType),
      (l10n.detailRatio, item.ratio),
      // Both are omitted, not zeroed, where the source publishes no such
      // figure: "0 views" is a claim, and it would be a false one.
      if (item.views case final int views) (l10n.detailViews, _number(views)),
      if (item.favorites case final int favorites)
        (l10n.detailFavorites, _number(favorites)),
    ];
  }

  String _bytes(AppLocalizations l10n, int bytes) =>
      l10n.detailFileSizeBytes(_number(bytes));

  String _number(int value) => NumberFormat.decimalPattern().format(value);

  /// Where this wallpaper came from and where it leads — credit, not fact.
  ///
  /// These sat in the key-value list beside views and favorites, which read
  /// them as data when every one is somewhere you can *go*. Grouping them as
  /// actions is what let the facts above become uniformly tiles.
  List<Widget> _attribution(AppLocalizations l10n, WallpaperDetails item) {
    return <Widget>[
      _LinkAction(
        icon: Icons.person_outline,
        text: item.uploader.username,
        onTap: () => onFollow(UploaderLink(item.uploader.username)),
      ),
      _sourceCredit(l10n, item),
      _LinkAction(
        icon: Icons.open_in_new,
        text: l10n.detailViewOnWallhaven,
        onTap: () => onOpenLink(item.wallpaper.pageUrl),
      ),
    ];
  }

  /// The credited source: a tappable link when it is a web address, plain
  /// selectable text otherwise.
  ///
  /// Wallhaven's `source` is free text an uploader typed — often a URL, but
  /// sometimes a bare attribution — so only an `http(s)` address becomes a
  /// link; anything else stays copyable text rather than a control that would
  /// open nothing.
  Widget _sourceCredit(AppLocalizations l10n, WallpaperDetails item) {
    final Uri? url = _webUrl(item.source);
    if (url != null) {
      return _LinkAction(
        icon: Icons.link,
        text: item.source,
        onTap: () => onOpenLink(url),
      );
    }
    return _PlainCredit(
      label: l10n.detailSource,
      text: item.source.isEmpty ? l10n.detailNotProvided : item.source,
    );
  }

  /// [raw] as an absolute `http(s)` URL, or null when it is not one.
  Uri? _webUrl(String raw) {
    final Uri? url = Uri.tryParse(raw.trim());
    if (url == null || !url.isAbsolute) return null;
    return url.scheme == 'http' || url.scheme == 'https' ? url : null;
  }
}

/// A glanceable fact at the top of the metadata panel.
class _MetadataTile extends StatelessWidget {
  const _MetadataTile({
    required this.width,
    required this.label,
    required this.value,
    super.key,
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

/// One place this wallpaper leads, styled as the link it is.
///
/// A [TextButton] rather than a tapped [Text]: it carries button semantics and
/// a real touch target, and a link only a sighted user with a steady thumb can
/// find is not a link. The icon carries the kind — who uploaded it, where it
/// came from, where it lives — so these need no labels to stay distinguishable.
class _LinkAction extends StatelessWidget {
  const _LinkAction({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        // No horizontal padding: every action must start on the same pixel as
        // the fact grid's left edge, or the panel stops looking like a column.
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        icon: Icon(icon, size: 18),
        label: Text(text),
      ),
    );
  }
}

/// A credit that leads nowhere — free-text attribution, or its absence.
///
/// Labelled, because without an icon-bearing button beside it a bare name is
/// not self-evidently the source. Selectable so it can still be copied out.
class _PlainCredit extends StatelessWidget {
  const _PlainCredit({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(text)),
        ],
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
