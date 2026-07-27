import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';

/// What a toast is reporting, which decides its icon and its tone.
///
/// Two kinds, not five. Every message in this app is either "that worked" or
/// "that did not", and a taxonomy with more rungs than the messages have would
/// only invite arguing about which rung a message sits on.
enum ToastKind {
  /// The action did what it said. Quiet: the screen has usually already
  /// changed to show it.
  success,

  /// The action did not happen, and the user may want to try again.
  failure,
}

/// Shows tela's toast, replacing whatever is on screen.
///
/// One helper for all of them, because a wallpaper app shows most of its
/// toasts *over a wallpaper* and they have to stay legible and stay quiet at
/// the same time. The Material default did neither: an edge-to-edge stripe
/// across a 1204dip tablet, with no icon and nothing separating "downloaded"
/// from "couldn't download".
///
/// The decisions worth not re-litigating:
///
/// - **Floating and width-capped**, so it reads as a message about the thing
///   you just did rather than as a new bar bolted to the bottom of the app. On
///   a tablet a full-width toast is a stripe; capped, it stays near the action.
/// - **Opaque, never translucent.** Same lesson the frosted app bar taught
///   (A2): a wall of thumbnails showing through chrome reads as broken, and a
///   toast lands over exactly that.
/// - **It replaces rather than queues.** Batch actions and the quick sheet can
///   fire several in a row, and Material queues them — leaving the user
///   watching a backlog of stale messages drain, the last of which is the only
///   true one.
/// - **A failure lingers longer than a success.** The success is usually
///   confirming something the screen already shows; the failure is the only
///   place the news exists.
/// - **A toast with an action still goes away on its own.** Flutter's
///   `ScaffoldMessenger` deliberately never starts its dismissal timer for a
///   SnackBar that has an action *while accessible navigation is on* — the
///   reasoning being that a screen-reader user needs time to reach the button.
///   The result on a device with TalkBack enabled is a toast that sits there
///   until something else replaces it, which is what the queued-download toast
///   was doing. So this schedules its own dismissal.
///
/// ```dart
/// showTelaToast(messenger, l10n.detailDownloadSuccess);
/// showTelaToast(messenger, l10n.detailDownloadFailure,
///     kind: ToastKind.failure);
/// ```
void showTelaToast(
  ScaffoldMessengerState messenger,
  String message, {
  ToastKind kind = ToastKind.success,
  SnackBarAction? action,
  Duration? duration,
}) {
  final BuildContext context = messenger.context;
  final ColorScheme colors = Theme.of(context).colorScheme;
  final bool isFailure = kind == ToastKind.failure;
  final Duration life = duration ?? (isFailure ? _failureLife : _successLife);
  messenger.hideCurrentSnackBar();
  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> shown =
      messenger.showSnackBar(
        SnackBar(
          content: _ToastContent(message: message, isFailure: isFailure),
          backgroundColor: isFailure
              ? colors.errorContainer
              : colors.inverseSurface,
          behavior: SnackBarBehavior.floating,
          width: _toastWidth(context),
          duration: life,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          action: action,
        ),
      );
  // Only where the framework really does leave it up: scheduling a timer the
  // rest of the time would arm one on every toast in the app — including in
  // widget tests, which fail on a pending timer at teardown.
  if (action != null && MediaQuery.accessibleNavigationOf(context)) {
    _dismissAfter(shown, life);
  }
}

/// How long a toast that reports success stays up.
const Duration _successLife = Duration(seconds: 3);

/// Longer, because a failure is usually the only place the news exists.
const Duration _failureLife = Duration(seconds: 6);

/// Closes [shown] after [life], unless it has already gone.
///
/// Only for a toast carrying an action *and* only under accessible navigation,
/// which is the exact case `ScaffoldMessenger` declines to time out. The
/// `closed` future cancels the timer, so this can never reach past its own
/// toast and dismiss whichever one replaced it.
void _dismissAfter(
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> shown,
  Duration life,
) {
  final Timer timer = Timer(life, shown.close);
  unawaited(shown.closed.then((SnackBarClosedReason _) => timer.cancel()));
}

/// Wide enough to read, never wider than a comfortable line.
///
/// Returns null on a narrow screen, which lets the default insets apply: a
/// fixed width larger than the phone it is on overflows rather than shrinking.
double? _toastWidth(BuildContext context) {
  final double available = MediaQuery.sizeOf(context).width - 32;
  if (available <= _maxToastWidth) return null;
  return _maxToastWidth;
}

const double _maxToastWidth = 520;

/// The icon and the words, laid out so the icon cannot squash the text.
class _ToastContent extends StatelessWidget {
  const _ToastContent({required this.message, required this.isFailure});

  final String message;
  final bool isFailure;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color foreground = isFailure
        ? colors.onErrorContainer
        : colors.onInverseSurface;
    return Row(
      children: <Widget>[
        Icon(
          isFailure ? Icons.error_outline : Icons.check_circle_outline,
          size: 20,
          color: foreground,
          // The kind is carried by colour and glyph, both of which a screen
          // reader ignores, so it says which it is in words.
          semanticLabel: isFailure ? l10n.toastFailure : l10n.toastSuccess,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: TextStyle(color: foreground)),
        ),
      ],
    );
  }
}
