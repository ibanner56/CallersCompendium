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
 *   cache and hands Dart the **path** of that copy.
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
                    pendingInitialPath = null
                    initialPayloadPulled = true
                    result.success(path)
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
        val path = copyToCache(uri) ?: return
        if (initialPayloadPulled) {
            channel?.invokeMethod("fileOpened", path)
        } else {
            pendingInitialPath = path
        }
    }

    /** Copies the content of [uri] into a private cache file and returns its
     * path, or `null` on any error (intake then simply does nothing — the
     * native side never crashes the app). */
    private fun copyToCache(uri: Uri): String? {
        return try {
            val dir = File(cacheDir, "incoming_share").apply { mkdirs() }
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "bundle.json"
            val dest = File(dir, "${System.nanoTime()}-$name")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            } ?: return null
            dest.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
