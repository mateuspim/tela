/// Which physical volume the files-outside-gallery tier writes to.
///
/// A *location*, not a storage tier: the three tiers answer "who else can see
/// this file", and this answers "which disk". Built-in storage and a removable
/// card are the only two tela offers, because they are the only two a phone or
/// tablet has.
enum StorageVolumeKind {
  /// The built-in shared storage every device has.
  device,

  /// A removable SD card, present only when one is inserted.
  sdCard,
}
