package cc.pym.tela

import android.content.Context
import android.content.res.XmlResourceParser
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.xmlpull.v1.XmlPullParser

/**
 * What tela refuses to hand to Android's Auto Backup, pinned as a test because
 * the cost of getting it wrong is silent.
 *
 * Backup is **on by default**, it runs with no user action and no log anyone
 * reads, and a missing line here does not fail a build, a suite, or a device
 * pass — it just copies the private library into the owner's Google account.
 * The rules also live in two files that must agree (pre- and post-Android-12),
 * which is exactly the shape that drifts when only one of them is edited.
 *
 * The directory assertion is the point of the whole suite: an `exclude` naming
 * a path that no longer exists reads as protection and provides none, so the
 * string in the XML is checked against the directory [TelaDirectories] actually
 * writes rather than against a copy of itself.
 *
 * SDK 35 for the same reason every Robolectric suite here pins it — see
 * [ImageStorageTestCase].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupExclusionTest {
    private lateinit var context: Context

    @Before
    fun openContext() {
        context = ApplicationProvider.getApplicationContext()
    }

    @Test
    fun `the private library never leaves on a cloud backup`() {
        assertTrue(
            "filesDir/wallpapers must be excluded from Android 11's full-backup rules",
            exclusionsOf(R.xml.backup_rules).contains(privateLibraryExclusion("full-backup-content")),
        )
        assertTrue(
            "filesDir/wallpapers must be excluded from the Android 12+ cloud backup",
            exclusionsOf(R.xml.data_extraction_rules).contains(privateLibraryExclusion("cloud-backup")),
        )
    }

    /**
     * Device transfer is a separate section with its own defaults, so excluding
     * a path from the cloud says nothing about the cable.
     */
    @Test
    fun `the private library never leaves on a device transfer`() {
        assertTrue(
            "filesDir/wallpapers must be excluded from device-transfer too",
            exclusionsOf(R.xml.data_extraction_rules).contains(privateLibraryExclusion("device-transfer")),
        )
    }

    /** The older rule, which the private-library lines were added beside. */
    @Test
    fun `the encrypted api key is still left behind`() {
        val keyStore = BackupExclusion("", "sharedpref", "FlutterSecureStorage.xml")
        assertEquals(
            listOf("full-backup-content"),
            sectionsExcluding(R.xml.backup_rules, keyStore),
        )
        assertEquals(
            listOf("cloud-backup", "device-transfer"),
            sectionsExcluding(R.xml.data_extraction_rules, keyStore),
        )
    }

    /**
     * The exclusion is worthless if it names a directory the app stopped using,
     * and nothing else would notice: renaming the private tier's folder is a
     * one-line change in [TelaDirectories] that silently un-protects it.
     */
    @Test
    fun `the excluded path is the directory the private tier writes`() {
        val excluded = exclusionsOf(R.xml.backup_rules)
            .single { it.domain == "file" }
        assertEquals(
            TelaDirectories.privateImages(context),
            File(context.filesDir, excluded.path),
        )
    }

    /**
     * Tag folders inherit the exclusion, and that is why tags needed no rule of
     * their own.
     *
     * The `exclude` names a **directory**, so everything under it is excluded
     * whatever it is called — which is the whole reason a tag could be a real
     * folder in this tier without reopening the exposure closed on 2026-08-12.
     * Asserted rather than assumed, because "the private library is organized
     * now" and "the private library is still excluded" are two claims and only
     * one of them is obvious from the XML.
     */
    @Test
    fun `a tag folder inside the private tier is inside the excluded path`() {
        val excluded = File(context.filesDir, exclusionsOf(R.xml.backup_rules)
            .single { it.domain == "file" }
            .path)

        val tagged = TagFolders.privateDirectory(context, "anime")

        assertTrue(
            "a tagged private folder must sit under the excluded directory",
            tagged!!.canonicalPath.startsWith(excluded.canonicalPath + File.separator),
        )
    }

    private fun privateLibraryExclusion(section: String): BackupExclusion =
        BackupExclusion(section, "file", "wallpapers")

    private fun sectionsExcluding(resource: Int, exclusion: BackupExclusion): List<String> =
        exclusionsOf(resource)
            .filter { it.domain == exclusion.domain && it.path == exclusion.path }
            .map { it.section }

    /** Every `<exclude>` in [resource], tagged with the section enclosing it. */
    private fun exclusionsOf(resource: Int): List<BackupExclusion> {
        val parser = context.resources.getXml(resource)
        val found = mutableListOf<BackupExclusion>()
        var section = ""
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG) continue
            if (parser.name != "exclude") {
                section = parser.name
                continue
            }
            found += BackupExclusion(section, parser.attribute("domain"), parser.attribute("path"))
        }
        parser.close()
        return found
    }

    /**
     * Read by index rather than by name: these attributes carry no namespace,
     * and `getAttributeValue(null, …)` is the spelling that answers null on a
     * compiled resource depending on the parser behind it.
     */
    private fun XmlResourceParser.attribute(name: String): String {
        val index = (0 until attributeCount).firstOrNull { getAttributeName(it) == name }
        return index?.let { getAttributeValue(it) } ?: ""
    }
}

/** One `<exclude>` line: which section it sits in, and what it names. */
private data class BackupExclusion(val section: String, val domain: String, val path: String)
