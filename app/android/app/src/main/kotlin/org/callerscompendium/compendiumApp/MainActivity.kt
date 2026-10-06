package org.callerscompendium.compendiumApp

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

    // The size cap, the copy, and the cold-start vs warm routing live in
    // IncomingFileStager.kt, free of Android types so src/test can unit-test
    // them; this Activity only adapts Intent, Uri and MethodChannel onto them.
    private val stager = IncomingFileStager()
    private val router = IncomingPayloadRouter(
        push = { method, argument -> channel?.invokeMethod(method, argument) },
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> result.success(router.pullInitialFile())
                "getInitialUrl" -> result.success(router.pullInitialUrl())
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
            router.onSharedText(intent.getStringExtra(Intent.EXTRA_TEXT))
            return
        }
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        router.onFileStaged(copyToCache(uri))
    }

    /** Copies the content of [uri] into the private `incoming_share` cache
     * directory, through [IncomingFileStager] (which holds the size cap and
     * the cleanup). */
    private fun copyToCache(uri: Uri): StagedCopy =
        stager.stage(File(cacheDir, "incoming_share"), uri.lastPathSegment) {
            contentResolver.openInputStream(uri)
        }
}
