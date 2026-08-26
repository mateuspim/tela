/// Whether tela's notifications are allowed, and the way to Android's switch.
///
/// A port with **no setter, on purpose.** An Android app cannot turn its own
/// notifications on or off: the grant dialog is offered once and revoking is
/// the system's screen only. So the honest shape is "say whether they are on,
/// and take me where I can change it" — a switch tela drew itself would be
/// unable to honour either position.
///
/// It matters more here than in most apps: the offload and the download queue
/// run behind a foreground-service notification, so with this off the work the
/// user asked to happen in the background happens with nothing to show for it.
///
/// ```dart
/// if (!await notifications.areEnabled()) await notifications.openSettings();
/// ```
abstract interface class NotificationAccess {
  /// Whether anything tela posts would actually be shown.
  Future<bool> areEnabled();

  /// Opens Android's notification page for tela. Answers whether it opened.
  Future<bool> openSettings();
}
