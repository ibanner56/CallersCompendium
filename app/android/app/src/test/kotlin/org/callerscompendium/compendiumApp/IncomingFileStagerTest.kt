package org.callerscompendium.compendiumApp

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** JVM tests for the size cap, copy and cleanup behind MainActivity's
 * `copyToCache` (post-audit finding platform-7). */
class IncomingFileStagerTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val cap = 10L

    /** A small cap and a buffer smaller than it, so the cap is crossed part
     * way through a read loop rather than on the first read. */
    private fun stager(maxBytes: Long = cap) =
        IncomingFileStager(maxBytes = maxBytes, bufferBytes = 4, nanoTime = { 42L })

    private fun dir() = File(temp.root, "incoming_share")

    private fun bytes(n: Int) = ByteArray(n) { (it % 251).toByte() }

    private fun leftovers(): List<String> = dir().list()?.toList() ?: emptyList()

    @Test
    fun `a file exactly at the cap is staged in full`() {
        val content = bytes(cap.toInt())
        val result = stager().stage(dir(), "bundle.json") { ByteArrayInputStream(content) }

        assertTrue("expected Copied, got $result", result is StagedCopy.Copied)
        val staged = File((result as StagedCopy.Copied).path)
        assertEquals(File(dir(), "42-bundle.json").absolutePath, staged.absolutePath)
        assertArrayEquals(content, staged.readBytes())
    }

    @Test
    fun `one byte over the cap is refused and nothing is left behind`() {
        val result = stager().stage(dir(), "bundle.json") {
            ByteArrayInputStream(bytes(cap.toInt() + 1))
        }

        assertSame(StagedCopy.TooLarge, result)
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test
    fun `a source far over the cap stops reading once the cap is crossed`() {
        // A source that never ends (or lies about its length) must still be
        // bounded: the copy is counted as it streams.
        var served = 0L
        val endless = object : InputStream() {
            override fun read(): Int = throw AssertionError("bulk reads only")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                served += len
                return len
            }
        }
        val result = stager().stage(dir(), "bundle.json") { endless }

        assertSame(StagedCopy.TooLarge, result)
        assertTrue("read $served bytes past a $cap-byte cap", served <= cap + 4)
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test
    fun `a stream that fails mid-copy is Failed and cleans up`() {
        var reads = 0
        val failing = object : InputStream() {
            override fun read(): Int = throw AssertionError("bulk reads only")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (reads++ == 0) return 3 // some bytes reach the file first
                throw IOException("connection reset")
            }
        }
        val result = stager().stage(dir(), "bundle.json") { failing }

        assertSame(StagedCopy.Failed, result)
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test
    fun `a source that cannot be opened is Failed`() {
        assertSame(StagedCopy.Failed, stager().stage(dir(), "bundle.json") { null })
        assertSame(
            StagedCopy.Failed,
            stager().stage(dir(), "bundle.json") { throw SecurityException("no grant") },
        )
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test
    fun `an empty source is staged as an empty file`() {
        val result = stager().stage(dir(), "bundle.json") { ByteArrayInputStream(ByteArray(0)) }

        assertTrue(result is StagedCopy.Copied)
        assertEquals(0L, File((result as StagedCopy.Copied).path).length())
    }

    @Test
    fun `the copy is named from the last path segment after its last slash`() {
        fun nameFor(segment: String?): String {
            val result = stager().stage(dir(), segment) { ByteArrayInputStream(bytes(1)) }
            return File((result as StagedCopy.Copied).path).name
        }
        assertEquals("42-share.ccshare", nameFor("share.ccshare"))
        // Some providers put an encoded path in the last segment.
        assertEquals("42-share.json", nameFor("primary:Download/share.json"))
        assertEquals("42-bundle.json", nameFor(null))
    }

    @Test
    fun `the default cap is 25 MiB`() {
        assertEquals(25L * 1024 * 1024, IncomingFileStager.MAX_INCOMING_BYTES)
    }

    @Test
    fun `the default stager stages a file at 25 MiB and refuses one byte more`() {
        val atCap = IncomingFileStager.MAX_INCOMING_BYTES
        fun sized(n: Long) = object : InputStream() {
            var left = n
            override fun read(): Int = throw AssertionError("bulk reads only")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (left == 0L) return -1
                val count = minOf(len.toLong(), left).toInt()
                left -= count
                return count
            }
        }

        val atResult = IncomingFileStager().stage(dir(), "a.json") { sized(atCap) }
        assertTrue("expected Copied, got $atResult", atResult is StagedCopy.Copied)
        assertEquals(atCap, File((atResult as StagedCopy.Copied).path).length())
        File(atResult.path).delete()

        val overResult = IncomingFileStager().stage(dir(), "b.json") { sized(atCap + 1) }
        assertSame(StagedCopy.TooLarge, overResult)
        assertEquals(emptyList<String>(), leftovers())
    }

    @Test
    fun `deleteStagedCopy removes the file and tolerates a missing one`() {
        val file = temp.newFile("staged.json")
        deleteStagedCopy(file.absolutePath)
        assertTrue(!file.exists())
        deleteStagedCopy(file.absolutePath) // already gone: no throw
    }
}
