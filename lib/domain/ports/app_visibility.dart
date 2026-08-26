/// Whether tela has a screen in front of the user right now.
///
/// A port because the answer comes from the Flutter binding, which `domain` may
/// not import — but mostly because of *what it is for*, which is narrower and
/// more specific than "app lifecycle":
///
/// **One step of a storage move cannot happen in the background at all.** From
/// API 30 a gallery-tier delete goes through `MediaStore.createDeleteRequest`,
/// the OS's own confirmation, and only an Activity can launch it. With none
/// attached the platform answers honestly that nothing was deleted — and a
/// move reads that as a declined delete and undoes every copy behind it. A
/// batch that spent four minutes copying to a card would silently unwind
/// because the user switched apps while it ran.
///
/// So a background move copies freely and then *waits here* before deleting.
///
/// ```dart
/// await visibility.whenForeground(); // then, and only then, delete
/// ```
abstract interface class AppVisibility {
  /// Whether a screen is attached and resumed this instant.
  bool get isForeground;

  /// Completes as soon as [isForeground] is true — immediately when it already
  /// is.
  ///
  /// Never times out and never throws. There is no useful failure: the work is
  /// already anchored by a foreground service, the copies are safely on disk,
  /// and the honest thing for a move whose user has walked away is to be there
  /// when they come back.
  Future<void> whenForeground();
}
