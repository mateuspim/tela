package cc.pym.tela

import android.content.Context
import java.io.File

/**
 * The user's tag as a directory: what may become one, and where each tier puts
 * it.
 *
 * A tag in tela is not a label in a database, it is a **real folder** — the
 * gallery tier's `Pictures/tela/anime`, the files tier's `tela/anime`, the
 * private tier's `wallpapers/anime`. That is what makes a tag organize the
 * library in Photos, in a file manager and over USB rather than only inside the
 * app, and it is what lets the app-private tier be organized at all: that tier
 * writes no database row on purpose, so a folder is the only index it may have.
 *
 * Two jobs, and they are here together because separating them is how a guard
 * drifts from the path it guards:
 *
 * - **[isValid] is a path-traversal gate.** A tag arrives over a method channel
 *   and is concatenated into a directory name, so `../../databases` must never
 *   reach a file system call — the same danger [ImageFileNaming]'s allowlist and
 *   [StoredImageReading.releasePreview]'s confinement already answer. It is
 *   deliberately stricter than "what a filename may contain": `.` is refused
 *   outright, which makes `..`, `.nomedia` and hidden directories all
 *   unreachable without reasoning about any of them individually.
 * - **[galleryPath] and [privateDirectory] are the one composition each.** The
 *   gallery writer and its duplicate lookup must agree on the directory or a
 *   re-download stops finding the file it wrote, and three spellings of
 *   `File(filesDir, "wallpapers/$tag")` is exactly the drift [TelaDirectories]
 *   exists to prevent.
 *
 * A null tag is the untagged root everywhere, which is what every caller passed
 * before tags existed and is why they keep working unchanged.
 *
 * ```
 * TagFolders.isValid("anime")        // true
 * TagFolders.isValid("../secrets")   // false
 * TagFolders.galleryPath("anime")    // "Pictures/tela/anime"
 * ```
 */
internal object TagFolders {
    /**
     * Whether [tag] may be used as a directory name.
     *
     * Letters, digits, space, `_` and `-`, one to 32 characters. No separator,
     * no `.`, nothing else — an allowlist rather than a blocklist, so a
     * character nobody thought about is refused rather than passed through.
     * Dart validates the same shape in `TagFolder` before it ever gets here;
     * this is the gate that does not trust it, because this is the side holding
     * the file system.
     */
    fun isValid(tag: String): Boolean = VALID_TAG.matches(tag)

    /**
     * MediaStore's `RELATIVE_PATH` for a gallery download, tagged or not.
     *
     * Both the insert and [TierWriting]'s duplicate lookup read this. They must
     * name the same directory: the lookup is scoped to a path as well as a file
     * name — another app's `wallhaven-abc123.jpg` elsewhere is not ours to
     * overwrite — so a second spelling here would make a re-download insert a
     * duplicate instead of rewriting the file it already has.
     */
    fun galleryPath(tag: String?): String {
        if (tag == null) return TreeLocation.GALLERY_FOLDER_PATH
        return "${TreeLocation.GALLERY_FOLDER_PATH}/$tag"
    }

    /**
     * The app-private directory a tagged image lives in, or the tier root.
     *
     * Answers null for a tag that fails [isValid], so a caller cannot reach the
     * file system with one — the refusal is a return value rather than a throw
     * because every caller already has an `imageStoreFailure` to answer with.
     */
    fun privateDirectory(context: Context, tag: String?): File? {
        val root = TelaDirectories.privateImages(context)
        if (tag == null) return root
        if (!isValid(tag)) return null
        return File(root, tag)
    }

    /**
     * The tag a private file's parent directory names, or null when it sits in
     * the tier root.
     *
     * The read half of [privateDirectory], for [PrivateTierListing]: a private
     * image's tag is not recorded anywhere but the directory holding it, for the
     * same reason its source is not recorded anywhere but its file name.
     */
    fun tagOf(context: Context, file: File): String? {
        val parent = file.parentFile ?: return null
        val root = TelaDirectories.privateImages(context)
        if (parent.absolutePath == root.absolutePath) return null
        return parent.name.takeIf(::isValid)
    }

    /**
     * Deliberately without `.`, and that is the whole traversal guard: no `..`,
     * no `.nomedia`, no hidden directory, without a rule per case. Mirrors the
     * shape of [ImageFileNaming]'s allowlists, one character class narrower.
     *
     * A space is allowed **inside** a tag and refused at either end, which is
     * why this is not one flat character class. `"sci fi"` is a name someone
     * would reasonably type; `" anime"` and `"anime "` are folders that render
     * identically to `"anime"` in every list the user will ever see while being
     * a different directory on disk, and a tag the user cannot tell apart from
     * another is worse than a refused one. Total length stays 1–32.
     */
    private val VALID_TAG = Regex("[A-Za-z0-9_-]([A-Za-z0-9 _-]{0,30}[A-Za-z0-9_-])?")
}
