package org.callerscompendium.compendiumApp

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Receive-side share import (issues #298 + #343): forwards an incoming shared
 * payload to the Dart intake over the
 * `is.banner.callerscompendium/incoming_files` channel. Two payload kinds:
 *
 * - **File** (#298): a shared CompendiumArchive `.json` bundle (AirDrop-style
 *   share / "Open with"). The native side copies it into the app's private
 *   cache and hands Dart an ownership-marked payload containing the path of
 *   that copy.
 * - **URL** (#343): a web page URL shared as `text/plain` from a browser (an
 *   `ACTION_SEND` with `EXTRA_TEXT`). The native side hands Dart the **raw URL
 *   string** verbatim.
 *
 * The native side never parses, trusts, or interprets a payload — Dart owns all
 * validation and import (both the file, via `ArchiveIntakeService`, and the URL,
 * via `validateSharedContraDbProgramUrl`, are untrusted input).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "is.banner.callerscompendium/incoming_files"
    private var channel: MethodChannel? = null

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

    /** Set once Dart pulls the cold-start payload. Before this, an incoming
     * payload is the launch payload (retained for the pull); after it, an
     * incoming payload is a warm event pushed on the stream — so exactly one
     * import happens per payload, never a cold/warm double. */
    private var initialPayloadPulled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    val path = pendingInitialPath
                    val tooLarge = pendingInitialTooLarge
                    pendingInitialPath = null
                    pendingInitialTooLarge = false
                    initialPayloadPulled = true
                    result.success(
                        when {
                            path != null -> filePayload(path)
                            tooLarge -> tooLargePayload()
                            else -> null
                        }
                    )
                }
                "getInitialUrl" -> {
                    val url = pendingInitialUrl
                    pendingInitialUrl = null
                    initialPayloadPulled = true
                    result.success(url)
                }
                else -> result.notImplemented()
            }
        }
        channel = methodChannel
        // The intent that launched the activity may carry a payload to open.
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        // A text/plain share (issue #343): the URL rides in EXTRA_TEXT, not
        // EXTRA_STREAM. Handle it before the file path so a browser share isn't
        // mistaken for a file. The native side forwards the raw string verbatim;
        // Dart validates it as untrusted input.
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (text.isNullOrEmpty()) return
            if (initialPayloadPulled) {
                channel?.invokeMethod("urlShared", text)
            } else {
                pendingInitialUrl = text
            }
            return
        }
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        val staged = copyToCache(uri)
        if (staged is StagedCopy.TooLarge) {
            // Nothing was kept; tell Dart so the user sees the size rejection
            // instead of a share that silently does nothing.
            if (initialPayloadPulled) {
                channel?.invokeMethod("fileOpened", tooLargePayload())
            } else {
                pendingInitialTooLarge = true
            }
            return
        }
        val path = (staged as? StagedCopy.Copied)?.path ?: return
        if (initialPayloadPulled) {
            channel?.invokeMethod("fileOpened", filePayload(path))
        } else {
            pendingInitialPath?.let(::deleteStagedCopy)
            pendingInitialPath = path
            pendingInitialTooLarge = false
        }
    }

    private fun filePayload(path: String): Map<String, Any> =
        mapOf("path" to path, "appOwned" to true)

    private fun tooLargePayload(): Map<String, Any> =
        mapOf("rejected" to "tooLarge")

    /** Outcome of staging an incoming file. */
    private sealed class StagedCopy {
        class Copied(val path: String) : StagedCopy()
        object TooLarge : StagedCopy()
        object Failed : StagedCopy()
    }

    /** Copies the content of [uri] into a private cache file, refusing to write
     * more than [MAX_INCOMING_BYTES]. The copy is counted as it streams, so a
     * source that under-reports (or does not report) its length is still bounded,
     * and the partial file is deleted on rejection or error. [StagedCopy.Failed]
     * on any other error (intake then simply does nothing — the native side never
     * crashes the app). */
    private fun copyToCache(uri: Uri): StagedCopy {
        val dir = File(cacheDir, "incoming_share")
        val name = uri.lastPathSegment?.substringAfterLast('/') ?: "bundle.json"
        val dest = File(dir, "${System.nanoTime()}-$name")
        return try {
            dir.mkdirs()
            val input = contentResolver.openInputStream(uri) ?: return StagedCopy.Failed
            var tooLarge = false
            input.use {
                FileOutputStream(dest).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_BYTES)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_INCOMING_BYTES) {
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

    private fun deleteStagedCopy(path: String) {
        try {
            val file = File(path)
            if (file.exists()) file.delete()
        } catch (_: Exception) {
            // A failed cleanup must not crash the activity while handling an
            // already-failed or superseded share.
        }
    }

    private companion object {
        /** Must equal `kMaxIncomingArchiveBytes` in
         * `lib/src/data/archive_intake_service.dart` (25 MiB); a Dart test
         * (`incoming_native_limits_test.dart`) fails if they drift. */
        const val MAX_INCOMING_BYTES = 26214400L
        const val COPY_BUFFER_BYTES = 8192
    }
}
