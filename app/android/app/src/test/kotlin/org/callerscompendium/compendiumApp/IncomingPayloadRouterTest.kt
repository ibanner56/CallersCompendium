package org.callerscompendium.compendiumApp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** JVM tests for the cold-start vs warm routing behind MainActivity's
 * `getInitialFile` / `getInitialUrl` pulls and `fileOpened` / `urlShared`
 * pushes (post-audit finding platform-7). */
class IncomingPayloadRouterTest {
    private val pushed = mutableListOf<Pair<String, Any>>()
    private val discarded = mutableListOf<String>()
    private val router = IncomingPayloadRouter(
        push = { method, argument -> pushed += method to argument },
        discardStagedCopy = { discarded += it },
    )

    private fun file(path: String) = mapOf("path" to path, "appOwned" to true)
    private val tooLarge = mapOf("rejected" to "tooLarge")

    @Test
    fun `a cold-start file is held for the pull, then consumed`() {
        router.onFileStaged(StagedCopy.Copied("/c/a.json"))

        assertEquals(emptyList<Any>(), pushed)
        assertEquals(file("/c/a.json"), router.pullInitialFile())
        assertNull(router.pullInitialFile())
    }

    @Test
    fun `a file after the pull is pushed as fileOpened, not held`() {
        assertNull(router.pullInitialFile())
        router.onFileStaged(StagedCopy.Copied("/c/b.json"))

        assertEquals(listOf("fileOpened" to file("/c/b.json")), pushed)
        assertNull(router.pullInitialFile())
    }

    @Test
    fun `pulling the URL also ends the cold-start window for files`() {
        assertNull(router.pullInitialUrl())
        router.onFileStaged(StagedCopy.Copied("/c/b.json"))

        assertEquals(listOf("fileOpened" to file("/c/b.json")), pushed)
    }

    @Test
    fun `a cold-start file that was too large pulls as the tooLarge payload`() {
        router.onFileStaged(StagedCopy.TooLarge)

        assertEquals(emptyList<Any>(), pushed)
        assertEquals(tooLarge, router.pullInitialFile())
        assertNull(router.pullInitialFile())
    }

    @Test
    fun `a warm file that was too large is pushed as the tooLarge payload`() {
        router.pullInitialFile()
        router.onFileStaged(StagedCopy.TooLarge)

        assertEquals(listOf("fileOpened" to tooLarge), pushed)
    }

    @Test
    fun `a too-large rejection never displaces a staged cold-start file`() {
        router.onFileStaged(StagedCopy.Copied("/c/a.json"))
        router.onFileStaged(StagedCopy.TooLarge)

        assertEquals(file("/c/a.json"), router.pullInitialFile())
        assertEquals(emptyList<String>(), discarded)
    }

    @Test
    fun `a staged file after a too-large rejection wins the pull, once`() {
        // MainActivity also clears the held rejection when a file is staged;
        // the pull consumes both anyway, so that reset is not observable here
        // and no assertion pins it.
        router.onFileStaged(StagedCopy.TooLarge)
        router.onFileStaged(StagedCopy.Copied("/c/a.json"))

        assertEquals(file("/c/a.json"), router.pullInitialFile())
        assertNull(router.pullInitialFile())
    }

    @Test
    fun `a newer cold-start file supersedes and deletes the unpulled one`() {
        router.onFileStaged(StagedCopy.Copied("/c/old.json"))
        router.onFileStaged(StagedCopy.Copied("/c/new.json"))

        assertEquals(listOf("/c/old.json"), discarded)
        assertEquals(file("/c/new.json"), router.pullInitialFile())
    }

    @Test
    fun `a failed copy is dropped silently, cold or warm`() {
        router.onFileStaged(StagedCopy.Failed)
        assertNull(router.pullInitialFile())
        router.onFileStaged(StagedCopy.Failed)

        assertEquals(emptyList<Any>(), pushed)
    }

    @Test
    fun `a failed copy does not displace a held cold-start file`() {
        router.onFileStaged(StagedCopy.Copied("/c/a.json"))
        router.onFileStaged(StagedCopy.Failed)

        assertEquals(file("/c/a.json"), router.pullInitialFile())
        assertEquals(emptyList<String>(), discarded)
    }

    @Test
    fun `shared text is trimmed and held for the cold-start URL pull`() {
        router.onSharedText("  https://example.org/p  \n")

        assertEquals(emptyList<Any>(), pushed)
        assertEquals("https://example.org/p", router.pullInitialUrl())
        assertNull(router.pullInitialUrl())
    }

    @Test
    fun `shared text after the pull is pushed as urlShared`() {
        router.pullInitialFile()
        router.onSharedText("https://example.org/p")

        assertEquals(listOf("urlShared" to "https://example.org/p"), pushed)
    }

    @Test
    fun `blank or missing shared text is ignored`() {
        router.onSharedText(null)
        router.onSharedText("   ")
        assertNull(router.pullInitialUrl())
        router.onSharedText("")
        router.onSharedText(null)

        assertEquals(emptyList<Any>(), pushed)
    }

    @Test
    fun `a held URL and a held file are pulled independently`() {
        router.onSharedText("https://example.org/p")
        router.onFileStaged(StagedCopy.Copied("/c/a.json"))

        assertEquals(file("/c/a.json"), router.pullInitialFile())
        assertEquals("https://example.org/p", router.pullInitialUrl())
    }
}
