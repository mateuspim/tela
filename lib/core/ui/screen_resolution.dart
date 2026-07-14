import 'package:flutter/widgets.dart';
import 'package:tela/domain/models/resolution.dart';

/// The pixel size of the screen this widget is being built on.
///
/// Every listing asks Wallhaven for images at least this large. Without it the
/// grid fills with 1280x720 images that look soft the moment they are set as a
/// wallpaper on a 1440p phone — so browse and every listing pushed from it must
/// answer the question the same way.
///
/// ```dart
/// query.copyWith(atLeast: screenResolution(context));
/// ```
Resolution screenResolution(BuildContext context) {
  final Size size = MediaQuery.sizeOf(context);
  final double ratio = MediaQuery.devicePixelRatioOf(context);
  return Resolution(
    (size.width * ratio).round(),
    (size.height * ratio).round(),
  );
}
