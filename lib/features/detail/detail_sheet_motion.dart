import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tela/features/detail/detail_editorial_body.dart';

/// Moving Detail's sheet without a finger on it: the grip's tap, the upward
/// throw over the picture, and the return to the peek.
///
/// Split out of [DetailEditorialBody] to keep that file under the 500-line
/// rule; the screen and the body both drive the sheet through here.
///
/// ```dart
/// DetailSheetMotion.revealSheet(sheet, animate: true);
/// ```
abstract final class DetailSheetMotion {
  /// How long the sheet takes to settle when something other than a finger
  /// moves it. Matches the pager's own page turn, so the screen has one speed.
  static const Duration sheetSettle = Duration(milliseconds: 240);

  /// Raises [sheet] to [DetailEditorialBody.restingSheetFraction], unless it
  /// is already at least that far up.
  ///
  /// The guard is not a tidiness check. The upward throw that calls this is
  /// armed across the whole picture, and a picture is still visible above a
  /// fully-raised sheet — so without it, flicking up on a sheet already at
  /// [DetailEditorialBody.fullSheetFraction] would *lower* it, which is the
  /// opposite of what the gesture says.
  static Future<void> revealSheet(
    DraggableScrollableController sheet, {
    required bool animate,
  }) {
    if (!sheet.isAttached ||
        sheet.size >= DetailEditorialBody.restingSheetFraction) {
      return Future<void>.value();
    }
    return moveSheet(
      sheet,
      extent: DetailEditorialBody.restingSheetFraction,
      animate: animate,
    );
  }

  /// Moves [sheet] to [extent], instantly where the platform asked for no
  /// motion.
  ///
  /// Static, and the single spelling of it, because three things now move this
  /// sheet without a finger on it: the grip's tap, the upward throw, and the
  /// return to the peek. A detached controller is an ordinary state, not an
  /// error — the sheet attaches on its first layout, and a gesture can arrive
  /// in the frame before that.
  ///
  /// **The check after the animation is not belt-and-braces.**
  /// `DraggableScrollableController.animateTo` registers an activity on the
  /// sheet, and *any* scroll activity beginning there cancels it — silently,
  /// with a future that then never completes. A Detail screen still arriving
  /// produces exactly those, so a throw in the first moments after opening did
  /// nothing at all (measured 2026-08-24: the first reveal after mount was
  /// swallowed every time, the next one worked). That is the same
  /// "sometimes it doesn't" this whole pass exists to end, so the sheet is put
  /// where it was asked to go.
  ///
  /// Only when it has not moved *at all*: a sheet the user grabbed mid-flight
  /// is somewhere else by now, and yanking it to the target would be the more
  /// annoying bug of the two.
  static Future<void> moveSheet(
    DraggableScrollableController sheet, {
    required double extent,
    required bool animate,
  }) async {
    if (!sheet.isAttached) return;
    if (!animate) {
      sheet.jumpTo(extent);
      return;
    }
    final double before = sheet.size;
    unawaited(
      sheet.animateTo(
        extent,
        duration: sheetSettle,
        curve: Curves.easeOutCubic,
      ),
    );
    await Future<void>.delayed(sheetSettle);
    if (!sheet.isAttached || sheet.size != before) return;
    sheet.jumpTo(extent);
  }
}
