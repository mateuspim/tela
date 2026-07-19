import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:tela/app/routes.dart';
import 'package:tela/core/ui/gallery_session_controller.dart';
import 'package:tela/domain/models/download_record.dart';

/// Opens the local-first viewer over [recent], positioned on [index].
///
/// Shared by the download-history grid and the Library hub's preview strip, so
/// a tap on a downloaded wallpaper means the same thing from either — and so
/// the session's ownership rules are written once.
///
/// The session is the **complete** local list, newest first, so it never pages:
/// the same complete-local-snapshot invariant Favorites holds. Its creator
/// disposes it when the viewer returns, which is why this owns the `try/finally`
/// rather than handing the session back to the caller.
///
/// ```dart
/// onTap: () => openDownloadViewer(context, recent, index);
/// ```
void openDownloadViewer(
  BuildContext context,
  List<DownloadRecord> recent,
  int index,
) {
  unawaited(_pushViewer(context, recent, index));
}

Future<void> _pushViewer(
  BuildContext context,
  List<DownloadRecord> recent,
  int index,
) async {
  final GallerySessionController<DownloadRecord> session =
      GallerySessionController<DownloadRecord>(
        identity: 'download-history',
        items: recent,
        initialIndex: index,
        itemKey: (DownloadRecord record) => record.wallpaper.id,
      );
  try {
    await context.pushNamed<void>(
      TelaRoutes.downloadViewerName,
      extra: session,
    );
  } finally {
    session.dispose();
  }
}
