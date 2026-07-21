package cc.pym.tela

import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.storage.StorageManager
import android.os.storage.StorageVolume

/**
 * The removable and built-in volumes the files-outside-gallery tier can target.
 *
 * The one place that talks to `StorageManager`. It is a thin adapter by design:
 * every selection decision lives in the pure [VolumeSelection], which tests can
 * reach, because Robolectric emulates no storage volumes and this wiring cannot
 * be exercised off a device.
 */
class DownloadVolumes(private val context: Context) {

    private val volumes: List<StorageVolume>
        get() = context.getSystemService(StorageManager::class.java)
            ?.storageVolumes.orEmpty()

    /** The built-in shared storage, or null if the platform withheld it. */
    fun primary(): StorageVolume? =
        VolumeSelection.primary(volumes) { it.isPrimary }

    /** A mounted removable card, or null when none is inserted. */
    fun sdCard(): StorageVolume? = VolumeSelection.sdCard(
        volumes,
        { it.isRemovable },
        { it.state == Environment.MEDIA_MOUNTED },
    )

    /** Whether a card is available to offer as a destination right now. */
    fun sdCardAvailable(): Boolean = sdCard() != null

    /** The volume a domain [kind] names, or null when that volume is absent. */
    fun forKind(kind: String): StorageVolume? = VolumeSelection.forKind(
        kind,
        volumes,
        { it.isPrimary },
        { it.isRemovable },
        { it.state == Environment.MEDIA_MOUNTED },
    )

    /**
     * The volume a granted tree sits on, matched by uuid.
     *
     * Null when the card that tree names is not in the device — which is not a
     * failure, it is exactly the ejected case the caller wants to hear about.
     */
    fun forLocation(location: TreeLocation): StorageVolume? {
        return volumes.firstOrNull { volume ->
            if (location.isPrimary) volume.isPrimary
            else volume.uuid.equals(location.volumeId, ignoreCase = true)
        }
    }

    /**
     * A folder picker already pointed at [kind]'s volume, or null when it is
     * absent (a card asked for while the slot is empty).
     *
     * Pre-aiming is the whole UX difference: `createOpenDocumentTreeIntent`
     * opens the system picker *at* the chosen volume, so the user confirms one
     * folder instead of hunting for the card in a blank tree browser.
     */
    fun openTreeIntentFor(kind: String): Intent? =
        forKind(kind)?.createOpenDocumentTreeIntent()
}
