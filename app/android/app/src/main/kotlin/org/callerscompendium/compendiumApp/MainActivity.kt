package org.callerscompendium.compendiumApp

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Receive-side share import (issue #298): forwards an incoming shared
 * CompendiumArchive `.json` bundle (AirDrop-equivalent share / "Open with")
 * to the Dart intake over the `is.banner.callerscompendium/incoming_files`
 * channel.
 *
 * The native side does one thing: copy the incoming file into the app's private
 * cache and hand Dart the **path** of that copy. It never parses, trusts, or
 * interprets the contents — Dart's `ArchiveIntakeService` owns all validation
 * and import (the file is untrusted input).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "is.banner.callerscompendium/incoming_files"
    private var channel: MethodChannel? = null

    /** Path captured from a launch (cold-start) intent, consumed once by the
     * `getInitialFile` pull. */
    private var pendingInitialPath: String? = null

    /** Set once Dart pulls the cold-start file. Before this, an incoming file is
     * the launch file (retained for the pull); after it, an incoming file is a
     * warm event pushed on the `files` stream — so exactly one import happens
     * per file, never a cold/warm double. */
    private var initialFilePulled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    val path = pendingInitialPath
                    pendingInitialPath = null
                    initialFilePulled = true
                    result.success(path)
                }
                else -> result.notImplemented()
            }
        }
        channel = methodChannel
        // The intent that launched the activity may carry a file to open.
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        val path = copyToCache(uri) ?: return
        if (initialFilePulled) {
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
