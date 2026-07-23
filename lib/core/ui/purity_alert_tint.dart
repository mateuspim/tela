import 'package:flutter/material.dart';
import 'package:tela/domain/models/purity.dart';

/// The tint a download affordance wears for [purity]; null when it needs none.
///
/// The question the colour answers is *"should I decide where this lands,
/// rather than let it route?"* — and sketchy and explicit both answer yes, so
/// they share one tint. Explicit defaults to the private library, but sketchy
/// follows the **safe** setting straight into the MediaStore-indexed gallery,
/// which is the case that surprises: a suggestive wallpaper appearing in
/// Photos because nothing on the way in said it was suggestive.
///
/// The colour is a reminder, not a legend — the purity has a name in the
/// Details grid and in the affordance's semantics label.
///
/// [ColorScheme.error] rather than a constant of our own: the accent splice in
/// `TelaTheme` leaves the error roles alone when the user picks an accent, so
/// it is the one warm role that cannot be repainted into the very accent it is
/// warning against.
///
/// ```dart
/// Icon(Icons.download_outlined, color: purityAlertTint(colors, purity));
/// ```
Color? purityAlertTint(ColorScheme colors, Purity purity) {
  return purity == Purity.sfw ? null : colors.error;
}
