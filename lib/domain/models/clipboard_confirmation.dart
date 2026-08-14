/// Who tells the user that an image reached the clipboard.
///
/// Android 13 (API 33) shows its own clipboard preview — a thumbnail of what
/// was just copied — for every `setPrimaryClip`. A toast of tela's on top of it
/// is the same news twice in the same corner of the screen, which the platform
/// guidance asks apps to stop doing. Below 33 nothing is shown at all, so a
/// copy that says nothing looks like a copy that failed.
///
/// The port reports which of the two happened; the UI owes a confirmation only
/// for [tela]. tela never decides this by reading an SDK level itself — that
/// belongs to the adapter that made the platform call.
///
/// ```dart
/// final ClipboardConfirmation shown = await share.clipboard(wallpaper);
/// if (shown == ClipboardConfirmation.tela) showTelaToast(messenger, copied);
/// ```
enum ClipboardConfirmation {
  /// Android showed its own clipboard preview; tela stays quiet.
  system,

  /// The platform showed nothing, so tela owes the confirmation.
  tela,
}
