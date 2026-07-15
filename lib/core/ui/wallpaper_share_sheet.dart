import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/share_option.dart';

/// Asks whether to share a wallpaper's link or its image file.
///
/// Only the [options] the wallpaper's purity allows are offered — an explicit
/// wallpaper is handed `[ShareOption.link]` alone, so the image tile never
/// appears for it (see [shareOptionsFor]). Resolves to null when the sheet is
/// dismissed.
///
/// ```dart
/// final ShareOption? choice =
///     await chooseShareOption(context, shareOptionsFor(wallpaper.purity));
/// ```
Future<ShareOption?> chooseShareOption(
  BuildContext context,
  List<ShareOption> options,
) {
  return showModalBottomSheet<ShareOption>(
    context: context,
    builder: (BuildContext context) => _shareSheet(context, options),
  );
}

Widget _shareSheet(BuildContext context, List<ShareOption> options) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(title: Text(l10n.detailShareTitle)),
        for (final ShareOption option in options) _shareTile(context, option),
      ],
    ),
  );
}

Widget _shareTile(BuildContext context, ShareOption option) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final _ShareTileCopy copy = _copyFor(option, l10n);
  return ListTile(
    leading: Icon(copy.icon),
    title: Text(copy.title),
    subtitle: Text(copy.subtitle),
    onTap: () => Navigator.pop(context, option),
  );
}

_ShareTileCopy _copyFor(ShareOption option, AppLocalizations l10n) {
  return switch (option) {
    ShareOption.link => _ShareTileCopy(
      Icons.link_outlined,
      l10n.detailShareLink,
      l10n.detailShareLinkDetail,
    ),
    ShareOption.image => _ShareTileCopy(
      Icons.image_outlined,
      l10n.detailShareImage,
      l10n.detailShareImageDetail,
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
