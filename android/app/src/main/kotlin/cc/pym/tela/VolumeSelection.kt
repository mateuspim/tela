package cc.pym.tela

/**
 * The rule for choosing a storage volume by kind, with no Android type in sight.
 *
 * Lifted off `StorageManager` on purpose: Robolectric stands up **no** storage
 * volumes at all (`getStorageVolumes()` is empty), so while this logic lived on
 * the manager it could not be tested without a device — and "which disk a
 * download lands on" is exactly the thing worth defending mechanically. Here it
 * is generic over the volume type, so a test drives it with plain fakes and the
 * device-only wiring in [DownloadVolumes] stays a thin set of accessors.
 */
object VolumeSelection {
    const val DEVICE = "device"
    const val SD_CARD = "sdCard"

    /** The built-in shared volume, or null when the list has none. */
    fun <T> primary(volumes: List<T>, isPrimary: (T) -> Boolean): T? =
        volumes.firstOrNull(isPrimary)

    /**
     * A card that is both removable and mounted, or null.
     *
     * Both conditions matter: an unmounted card is a slot with a card the system
     * cannot write to, which is no more usable than an empty one.
     */
    fun <T> sdCard(
        volumes: List<T>,
        isRemovable: (T) -> Boolean,
        isMounted: (T) -> Boolean,
    ): T? = volumes.firstOrNull { isRemovable(it) && isMounted(it) }

    /** The volume a domain [kind] names, or null when that volume is absent. */
    fun <T> forKind(
        kind: String,
        volumes: List<T>,
        isPrimary: (T) -> Boolean,
        isRemovable: (T) -> Boolean,
        isMounted: (T) -> Boolean,
    ): T? = when (kind) {
        DEVICE -> primary(volumes, isPrimary)
        SD_CARD -> sdCard(volumes, isRemovable, isMounted)
        else -> null
    }
}
