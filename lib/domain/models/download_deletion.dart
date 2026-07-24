/// What a hard delete of a downloaded file actually did.
///
/// A delete is not always a deletion: the gallery tier on Android 30+ routes
/// through the system's own "allow tela to delete?" prompt, which the user can
/// dismiss. That is a legitimate outcome, not a failure — nothing was deleted
/// and nothing went wrong — so it is a value here rather than a thrown
/// `ImageStoreFailure`, which stays reserved for a delete that was meant to
/// happen and could not (a revoked grant, an I/O error).
enum DownloadDeletion {
  /// The file is gone from its tier.
  deleted,

  /// The user dismissed the system delete prompt; the file is untouched.
  declined,
}
