import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// How long a gallery navigation lasts, collapsing to an instant cut under the
/// platform's reduce-motion setting.
///
/// A zero duration also collapses the shared-element [Hero] flight the fade
/// pairs with, so the whole transition becomes instant rather than fast.
///
/// ```dart
/// final Duration d = galleryTransitionDuration(context);
/// ```
Duration galleryTransitionDuration(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);
}

/// A go_router page that fades a shelf's destination in — pairing with the
/// tile-to-viewer [Hero] — and honours reduce-motion by cutting instantly.
///
/// ```dart
/// pageBuilder: (context, state) =>
///     fadeGalleryPage<void>(context: context, child: const DetailScreen());
/// ```
CustomTransitionPage<T> fadeGalleryPage<T>({
  required BuildContext context,
  required Widget child,
  LocalKey? key,
}) {
  final Duration duration = galleryTransitionDuration(context);
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (_, Animation<double> animation, _, Widget child) =>
        FadeTransition(opacity: animation, child: child),
    child: child,
  );
}
