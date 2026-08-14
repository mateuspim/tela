import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/sheet_header.dart';
import 'package:tela/domain/models/share_option.dart';

/// Asks how to hand a wallpaper out — its link, its image file, or a clipboard
/// copy of the image.
///
/// Only the [options] the wallpaper's purity allows are offered — an explicit
/// wallpaper is handed `[ShareOption.link]` alone, so neither bitmap tile ever
/// appears for it (see [shareOptionsFor]). Resolves to null when the sheet is
/// dismissed.
///
/// ```dart
/// final ShareOption? choice =
///     await chooseShareOption(
///       context,
///       shareOptionsFor(wallpaper.purity),
///       sourceName: 'Konachan',
///     );
/// ```
Future<ShareOption?> chooseShareOption(
  BuildContext context,
  List<ShareOption> options, {
  required String sourceName,
}) {
  return showModalBottomSheet<ShareOption>(
    context: context,
    builder: (BuildContext context) =>
        _shareSheet(context, options, sourceName),
  );
}

Widget _shareSheet(
  BuildContext context,
  List<ShareOption> options,
  String sourceName,
) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SheetHeader(title: l10n.detailShareTitle),
        for (final ShareOption option in options)
          _shareTile(context, option, sourceName),
      ],
    ),
  );
}

Widget _shareTile(
  BuildContext context,
  ShareOption option,
  String sourceName,
) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final _ShareTileCopy copy = _copyFor(option, l10n, sourceName);
  return ListTile(
    leading: Icon(copy.icon),
    title: Text(copy.title),
    subtitle: Text(copy.subtitle),
    onTap: () => Navigator.pop(context, option),
  );
}

_ShareTileCopy _copyFor(
  ShareOption option,
  AppLocalizations l10n,
  String sourceName,
) {
  return switch (option) {
    ShareOption.link => _ShareTileCopy(
      Icons.link_outlined,
      l10n.detailShareLink,
      l10n.detailShareLinkDetail(sourceName),
    ),
    ShareOption.image => _ShareTileCopy(
      Icons.image_outlined,
      l10n.detailShareImage,
      l10n.detailShareImageDetail,
    ),
    ShareOption.clipboard => _ShareTileCopy(
      Icons.content_copy_outlined,
      l10n.detailShareClipboard,
      l10n.detailShareClipboardDetail,
    ),
  };
}

/// The label, explanation, and icon for one share option's tile.
class _ShareTileCopy {
  const _ShareTileCopy(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}
