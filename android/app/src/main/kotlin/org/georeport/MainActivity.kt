package org.georeport

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives images shared from other apps (ACTION_SEND / SEND_MULTIPLE) and
 * hands them to Dart over the `georeport/share` channel as cache file paths.
 *
 * Shared content URIs are copied into the cache directory immediately, while
 * the read grant that came with the intent is certainly valid; a raw byte
 * copy keeps EXIF (the GPS position must survive for the capture flow).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pendingShares = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "georeport/share",
        ).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dart pulls whatever arrived before it was listening
                    // (cold start); later shares are pushed instead.
                    "getInitialShare" -> {
                        result.success(pendingShares.toList())
                        pendingShares.clear()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        deliver(collectSharedImages(intent))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        deliver(collectSharedImages(intent))
    }

    private fun deliver(paths: List<String>) {
        if (paths.isEmpty()) return
        val active = channel
        if (active != null) {
            active.invokeMethod("shared", paths)
        } else {
            pendingShares.addAll(paths)
        }
    }

    private fun collectSharedImages(intent: Intent?): List<String> {
        if (intent == null || intent.type?.startsWith("image/") != true) {
            return emptyList()
        }
        val uris = when (intent.action) {
            Intent.ACTION_SEND ->
                listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.filterNotNull() ?: emptyList()
            else -> emptyList()
        }
        // The same intent is seen again when the activity recreates; strip
        // the extras so one share never produces two capture prefills.
        if (uris.isNotEmpty()) {
            intent.removeExtra(Intent.EXTRA_STREAM)
            setIntent(intent)
        }
        return uris.mapNotNull(::copyToCache)
    }

    private fun copyToCache(uri: Uri): String? = runCatching {
        val name = displayNameOf(uri) ?: "shared-${System.currentTimeMillis()}.jpg"
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val target = File(dir, "${System.nanoTime()}-$name")
        contentResolver.openInputStream(uri)!!.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        target.absolutePath
    }.getOrNull()

    private fun displayNameOf(uri: Uri): String? = runCatching {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
    }.getOrNull()
}
