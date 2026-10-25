package com.personal.jingyaopaint

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Passes painting files opened from other apps ("open with JingyaoPaint") to
 * Flutter over the `jingyao/open_file` channel. See lib/share/incoming_files.dart.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** A file that launched the app, held until Flutter is ready to ask. */
    private var pendingFile: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeInitialFile") {
                    result.success(pendingFile)
                    pendingFile = null
                } else {
                    result.notImplemented()
                }
            }
        }
        readFile(intent)?.let { pendingFile = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readFile(intent)?.let { channel?.invokeMethod("openFile", it) }
    }

    /** The bytes of the file [intent] opens, or null if it opens none. */
    private fun readFile(intent: Intent?): ByteArray? {
        if (intent == null) return null
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> streamOf(intent)
            else -> null
        } ?: return null
        // Mark the intent handled, so recreating the activity (for example
        // after a configuration change) doesn't import the file twice.
        intent.action = Intent.ACTION_MAIN
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                val bytes = stream.readBytes()
                if (bytes.size <= MAX_FILE_BYTES) bytes else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private companion object {
        const val CHANNEL = "jingyao/open_file"

        /** Paintings are small JSON; refuse anything absurdly large. */
        const val MAX_FILE_BYTES = 50 * 1024 * 1024
    }
}
