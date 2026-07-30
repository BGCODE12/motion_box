package com.motionbox.motion_box

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.motionbox.motion_box.plugin.LibreCutsPlugin
import com.motionbox.motion_box.services.FFmpegRenderEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_ENGINE = "com.yourcompany.librecuts/engine"
        private const val CHANNEL_LEGACY = "com.motionbox.motion_box/librecuts_engine"
    }

    private var renderEngine: FFmpegRenderEngine? = null
    private val mainScope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Add LibreCutsPlugin
        val plugin = LibreCutsPlugin()
        flutterEngine.plugins.add(plugin)

        // 2. Direct fallback MethodChannel handler for engine channels
        renderEngine = FFmpegRenderEngine(applicationContext)

        val channelHandler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "extractFrame" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: run {
                        result.error("INVALID_ARGUMENT", "sourcePath is required", null)
                        return@MethodCallHandler
                    }
                    val timeMs = (call.argument<Number>("timeMs"))?.toLong() ?: 0L
                    val outputPath = call.argument<String>("outputPath") ?: run {
                        result.error("INVALID_ARGUMENT", "outputPath is required", null)
                        return@MethodCallHandler
                    }

                    mainScope.launch(Dispatchers.IO) {
                        val res = renderEngine?.extractFrame(sourcePath, timeMs, outputPath)
                        withContext(Dispatchers.Main) {
                            if (res is FFmpegRenderEngine.RenderResult.Success) {
                                result.success(res.outputPath)
                            } else {
                                result.error("EXTRACTION_FAILED", "Failed to extract frame", null)
                            }
                        }
                    }
                }
                "cancelExport", "cancelSessions" -> {
                    mainScope.launch(Dispatchers.IO) {
                        renderEngine?.cancelAllSessions()
                        withContext(Dispatchers.Main) {
                            result.success(true)
                        }
                    }
                }
                else -> {
                    plugin.onMethodCall(call, result)
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_ENGINE)
            .setMethodCallHandler(channelHandler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_LEGACY)
            .setMethodCallHandler(channelHandler)

        Log.d(TAG, "Registered MethodChannel handlers for $CHANNEL_ENGINE and $CHANNEL_LEGACY")
    }
}
