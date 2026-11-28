package org.callerscompendium.compendiumApp

import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** JVM tests for the device-backup marker behind MainActivity's
 * `no_backup` channel (sync-spec §3.3). */
class NoBackupMarkerTest {
    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun `a new installation has no marker until one is written`() {
        val marker = NoBackupMarker(temp.root)

        assertFalse(marker.exists())
        marker.write()
        assertTrue(marker.exists())
        assertTrue(NoBackupMarker(temp.root).exists())
    }

    @Test
    fun `writing again leaves an existing marker as it is`() {
        val file = File(temp.root, NoBackupMarker.FILE_NAME)
        file.writeBytes(byteArrayOf(7))

        NoBackupMarker(temp.root).write()

        assertArrayEquals(byteArrayOf(7), file.readBytes())
    }
}
