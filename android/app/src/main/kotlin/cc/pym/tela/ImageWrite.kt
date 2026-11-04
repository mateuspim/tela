package cc.pym.tela

import android.net.Uri
import java.io.OutputStream

/**
 * One write into a tier: where it goes, what it is called, and where its bytes
 * come from.
 *
 * The seam that lets a download and a local copy share all three tier writers.
 * Everything those writers know is hard-won and specific — MediaStore
 * de-duplicating rather than overwriting, the `.nomedia` marker, `"wt"` to
 * truncate, and which failure paths may delete what they just created — and a
 * second copy of it to serve local sources is precisely where that knowledge
 * would rot. So the only thing that varies is [writeBytes].
 */
internal class ImageWrite(
    val source: String,
    val id: String,
    val extension: String,
    val purity: String,
    val tier: String,
    val tag: String?,
    val localCopyFrom: Uri? = null,
    val expectedDigest: (() -> StreamDigest?)? = null,
    val writeBytes: (OutputStream) -> Unit,
) {
    val fileName: String get() = ImageFileNaming.fileName(source, id, extension)
    val mimeType: String get() = ImageFileNaming.mimeType(extension)
}

/**
 * The answer a successful write gives, naming the tag it **actually** used.
 *
 * Reported rather than assumed by the caller, for the reason the tier
 * already is: the adapter has the last word. A sweep that could not remove
 * an older copy, or a tier that ignored the tag, must not be described to
 * the user — or written into a history row — as the tag they asked for.
 */
internal fun storedAnswer(location: Uri, tag: String? = null): Map<String, Any> {
    val answer = mutableMapOf<String, Any>(
        "success" to true,
        "location" to location.toString(),
    )
    // Absent rather than null for an untagged write, so the response reads
    // back the same as it did before tags existed.
    if (tag != null) answer["tag"] = tag
    return answer
}
