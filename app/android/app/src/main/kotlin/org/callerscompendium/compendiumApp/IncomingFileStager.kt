package org.callerscompendium.compendiumApp

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

// The decision logic behind MainActivity's share intake, kept free of any
// Android framework type so the JVM unit tests in src/test can exercise it
// directly (post-audit finding platform-7). MainActivity only adapts Intent,
// Uri, ContentResolver and MethodChannel onto the seams below.

/** Outcome of staging an incoming file. */
internal sealed class StagedCopy {
    class Copied(val path: String) : StagedCopy()
    object TooLarge : StagedCopy()
    object Failed : StagedCopy()
}

/**
 * Copies an incoming file into [dir], refusing to write more than [maxBytes].
 *
 * The copy is counted as it streams, so a source that under-reports (or does
 * not report) its length is still bounded, and the partial file is deleted on
 * rejection or error. [StagedCopy.Failed] on any other error (intake then
 * simply does nothing — the native side never crashes the app).
 */
internal class IncomingFileStager(
    private val maxBytes: Long = MAX_INCOMING_BYTES,
    private val bufferBytes: Int = COPY_BUFFER_BYTES,
    private val nanoTime: () -> Long = System::nanoTime,
) {
    /**
     * Stages the stream [open] returns under [dir]. [lastPathSegment] is the
     * source URI's last path segment, used for the copy's file name (after its
     * last `/`), or `bundle.json` when there is none. [open] returning `null`
     * is [StagedCopy.Failed]; so is it throwing.
     */
    fun stage(dir: File, lastPathSegment: String?, open: () -> InputStream?): StagedCopy {
        val name = lastPathSegment?.substringAfterLast('/') ?: "bundle.json"
        val dest = File(dir, "${nanoTime()}-$name")
        return try {
            dir.mkdirs()
            val input = open() ?: return StagedCopy.Failed
            var tooLarge = false
            input.use {
                FileOutputStream(dest).use { output ->
                    val buffer = ByteArray(bufferBytes)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > maxBytes) {
                            tooLarge = true
                            break
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }
            if (tooLarge) {
                deleteStagedCopy(dest.absolutePath)
                StagedCopy.TooLarge
            } else {
                StagedCopy.Copied(dest.absolutePath)
            }
        } catch (e: Exception) {
            deleteStagedCopy(dest.absolutePath)
            StagedCopy.Failed
        }
    }

    companion object {
        /** Must equal `kMaxIncomingArchiveBytes` in
         * `lib/src/data/archive_intake_service.dart` (25 MiB); a Dart test
         * (`incoming_native_limits_test.dart`) fails if they drift. */
        const val MAX_INCOMING_BYTES = 26214400L
        const val COPY_BUFFER_BYTES = 8192
    }
}

/** Deletes a staged copy, swallowing any error: a failed cleanup must not
 * crash the activity while handling an already-failed or superseded share. */
internal fun deleteStagedCopy(path: String) {
    try {
        val file = File(path)
        if (file.exists()) file.delete()
    } catch (_: Exception) {
        // See above.
    }
}

/**
 * Routes staged payloads to Dart: cold-start (pulled once by `getInitialFile`
 * / `getInitialUrl`) versus warm (pushed as `fileOpened` / `urlShared`).
 *
 * Before Dart pulls the cold-start payload, an incoming payload is the launch
 * payload and is retained for the pull; after it, an incoming payload is a warm
 * event pushed through [push] — so exactly one import happens per payload,
 * never a cold/warm double. [push] receives the method name and its argument.
 */
internal class IncomingPayloadRouter(
    private val push: (method: String, argument: Any) -> Unit,
    private val discardStagedCopy: (String) -> Unit = ::deleteStagedCopy,
) {
    /** Path captured from a launch (cold-start) intent, consumed once by the
     * `getInitialFile` pull. */
    private var pendingInitialPath: String? = null

    /** Set when a launch (cold-start) file was refused as over the size cap.
     * Consumed by the `getInitialFile` pull only when no staged path is pending,
     * so a rejection never displaces a file that was staged successfully. */
    private var pendingInitialTooLarge = false

    /** URL captured from a launch (cold-start) intent, consumed once by the
     * `getInitialUrl` pull. */
    private var pendingInitialUrl: String? = null

    /** Set once Dart pulls the cold-start payload (either pull). */
    private var initialPayloadPulled = false

    /** The `getInitialFile` reply: the staged-file payload, else the
     * `tooLarge` payload, else `null`. Consumes both, and marks the cold-start
     * payload pulled. */
    fun pullInitialFile(): Map<String, Any>? {
        val path = pendingInitialPath
        val tooLarge = pendingInitialTooLarge
        pendingInitialPath = null
        pendingInitialTooLarge = false
        initialPayloadPulled = true
        return when {
            path != null -> filePayload(path)
            tooLarge -> tooLargePayload()
            else -> null
        }
    }

    /** The `getInitialUrl` reply. Consumes it, and marks the cold-start
     * payload pulled. */
    fun pullInitialUrl(): String? {
        val url = pendingInitialUrl
        pendingInitialUrl = null
        initialPayloadPulled = true
        return url
    }

    /** A `text/plain` share's `EXTRA_TEXT` (issue #343), forwarded trimmed
     * but otherwise verbatim; blank or absent text is ignored. */
    fun onSharedText(rawText: String?) {
        val text = rawText?.trim()
        if (text.isNullOrEmpty()) return
        if (initialPayloadPulled) {
            push("urlShared", text)
        } else {
            pendingInitialUrl = text
        }
    }

    /** The outcome of staging a shared or opened file. */
    fun onFileStaged(staged: StagedCopy) {
        if (staged is StagedCopy.TooLarge) {
            // Nothing was kept; tell Dart so the user sees the size rejection
            // instead of a share that silently does nothing.
            if (initialPayloadPulled) {
                push("fileOpened", tooLargePayload())
            } else {
                pendingInitialTooLarge = true
            }
            return
        }
        val path = (staged as? StagedCopy.Copied)?.path ?: return
        if (initialPayloadPulled) {
            push("fileOpened", filePayload(path))
        } else {
            // A newer launch file supersedes an unpulled one; the older copy
            // would otherwise never be cleaned up.
            pendingInitialPath?.let(discardStagedCopy)
            pendingInitialPath = path
            pendingInitialTooLarge = false
        }
    }

    companion object {
        fun filePayload(path: String): Map<String, Any> =
            mapOf("path" to path, "appOwned" to true)

        fun tooLargePayload(): Map<String, Any> =
            mapOf("rejected" to "tooLarge")
    }
}
