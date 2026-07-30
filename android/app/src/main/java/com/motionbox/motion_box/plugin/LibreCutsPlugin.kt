package com.motionbox.motion_box.plugin

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.motionbox.motion_box.models.VideoProject
import com.motionbox.motion_box.services.FFmpegRenderEngine
import com.motionbox.motion_box.utils.ProjectSerializer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File

class LibreCutsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "LibreCutsPlugin"
        private const val METHOD_CHANNEL_NAME = "com.yourcompany.librecuts/engine"
        private const val EVENT_CHANNEL_NAME = "com.yourcompany.librecuts/export_progress"
    }

    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var renderEngine: FFmpegRenderEngine? = null
    private val pluginScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        renderEngine = FFmpegRenderEngine(binding.applicationContext)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel?.setStreamHandler(this)

        Log.d(TAG, "LibreCutsPlugin attached to Flutter Engine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        renderEngine?.cleanup()
        renderEngine = null
        context = null
        pluginScope.cancel()
        Log.d(TAG, "LibreCutsPlugin detached from Flutter Engine")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "renderExport" -> handleRenderExport(call, result)
            "cancelExport" -> handleCancelExport(result)
            "extractAudio" -> handleExtractAudio(call, result)
            "extractFrame" -> handleExtractFrame(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleRenderExport(call: MethodCall, result: MethodChannel.Result) {
        val engine = renderEngine ?: run {
            Log.e(TAG, "handleRenderExport: FFmpegRenderEngine is null")
            result.error("NO_ENGINE", "FFmpegRenderEngine is null", null)
            return
        }

        val recipeJson  = call.argument<String>("recipe")
        val sourcePath  = call.argument<String>("sourcePath")
        val outputPath  = call.argument<String>("outputPath") ?: run {
            Log.e(TAG, "handleRenderExport: outputPath argument is missing")
            result.error("INVALID_ARGUMENT", "outputPath is required", null)
            return
        }
        val resolution  = call.argument<Int>("resolution")     ?: 1080
        val fps         = call.argument<Int>("fps")            ?: 30
        val audioOnly   = call.argument<Boolean>("audioOnly")  ?: false
        val fontAssetPath = call.argument<String>("fontAssetPath") ?: "fonts/Roboto-Regular.ttf"

        // FIX BUG #2: Kotlin's `?:` only guards null, NOT empty strings.
        // Use isNullOrBlank() to treat "" the same as null.
        val hasRecipe = !recipeJson.isNullOrBlank()
        val hasSource = !sourcePath.isNullOrBlank()

        Log.d(TAG, "handleRenderExport ─────────────────────────────────────")
        Log.d(TAG, "  hasRecipe  : $hasRecipe  (${recipeJson?.length ?: 0} chars)")
        Log.d(TAG, "  sourcePath : '${sourcePath ?: "(null)"}'  hasSource=$hasSource")
        Log.d(TAG, "  outputPath : $outputPath")
        Log.d(TAG, "  resolution : $resolution  fps: $fps  audioOnly: $audioOnly")

        if (!hasRecipe && !hasSource) {
            Log.e(TAG, "handleRenderExport: both recipe and sourcePath are missing/empty")
            result.error("INVALID_ARGUMENT", "Either 'recipe' JSON or a non-empty 'sourcePath' must be provided", null)
            return
        }

        pluginScope.launch(Dispatchers.IO) {
            // FIX BUG #3: Guarantee result is ALWAYS resolved.
            // A single outer try/catch ensures result.error() fires even if
            // withContext(Dispatchers.Main) itself throws (e.g. scope cancelled).
            try {
                Log.d(TAG, "Copying font asset: $fontAssetPath")
                val fontPath = try {
                    engine.copyFontToCache(fontAssetPath)
                } catch (fontEx: Exception) {
                    Log.w(TAG, "Font copy failed (using null): ${fontEx.message}")
                    null  // Non-fatal: text overlays will render without custom font
                }

                val project: VideoProject = if (hasRecipe) {
                    Log.d(TAG, "Deserializing recipe JSON (${recipeJson!!.length} chars)...")
                    val recipe = ProjectSerializer.deserialize(recipeJson)
                    recipe.toVideoProject()
                } else {
                    Log.d(TAG, "No recipe — building bare VideoProject from sourcePath")
                    val uri = android.net.Uri.fromFile(java.io.File(sourcePath!!))
                    VideoProject(sourceUri = uri, sourceName = java.io.File(sourcePath).name)
                }

                // FIX BUG #2 (continued): Use isNullOrBlank() to pick the real path.
                // Kotlin ?: only handles null; empty string falls through unchanged.
                val primarySourcePath: String = when {
                    !sourcePath.isNullOrBlank() -> sourcePath
                    !project.sourceUri.path.isNullOrBlank() -> project.sourceUri.path!!
                    else -> project.sourceUri.toString()
                }

                if (primarySourcePath.isBlank()) {
                    Log.e(TAG, "primarySourcePath resolved to blank — cannot render")
                    withContext(Dispatchers.Main) {
                        sendEvent(mapOf("status" to "error", "message" to "Source video path is empty"))
                        result.error("INVALID_ARGUMENT", "Source video path resolved to empty string", null)
                    }
                    return@launch
                }

                Log.d(TAG, "Primary source path: $primarySourcePath")
                Log.d(TAG, "Starting FFmpeg render...")
                sendEvent(mapOf("status" to "rendering", "progress" to 0))

                val renderResult = engine.renderProject(
                    project           = project,
                    sourceFilePath    = primarySourcePath,
                    outputFilePath    = outputPath,
                    exportResolution  = resolution,
                    exportFps         = fps,
                    exportAudioOnly   = audioOnly,
                    fontFilePath      = fontPath,
                    onProgress        = { progress ->
                        Log.d(TAG, "Render progress: $progress%")
                        sendEvent(mapOf("status" to "rendering", "progress" to progress))
                    }
                )

                withContext(Dispatchers.Main) {
                    when (renderResult) {
                        is FFmpegRenderEngine.RenderResult.Success -> {
                            Log.d(TAG, "Render SUCCESS: ${renderResult.outputPath}")
                            saveToMediaStore(context, renderResult.outputPath)
                            sendEvent(mapOf("status" to "success", "outputPath" to renderResult.outputPath))
                            result.success(renderResult.outputPath)
                        }
                        is FFmpegRenderEngine.RenderResult.Failure -> {
                            Log.e(TAG, "Render FAILURE: ${renderResult.error}")
                            sendEvent(mapOf("status" to "error", "message" to renderResult.error))
                            result.error("EXPORT_FAILED", renderResult.error, null)
                        }
                        is FFmpegRenderEngine.RenderResult.Cancelled -> {
                            Log.d(TAG, "Render CANCELLED")
                            sendEvent(mapOf("status" to "cancelled"))
                            result.error("CANCELLED", "Export was cancelled", null)
                        }
                    }
                }

            } catch (e: Exception) {
                // FIX BUG #3: This outer catch guarantees result is ALWAYS resolved.
                // Without this, any exception thrown before withContext(Main) would
                // leave the Dart invokeMethod() awaiting forever.
                Log.e(TAG, "Unhandled exception in handleRenderExport: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    sendEvent(mapOf("status" to "error", "message" to (e.message ?: "Unknown error")))
                    result.error("EXCEPTION", e.message ?: "Unknown error in export engine", null)
                }
            }
        }
    }


    private fun handleCancelExport(result: MethodChannel.Result) {
        pluginScope.launch(Dispatchers.IO) {
            renderEngine?.cancelAllSessions()
            withContext(Dispatchers.Main) {
                sendEvent(mapOf("status" to "cancelled"))
                result.success(true)
            }
        }
    }

    private fun handleExtractAudio(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath") ?: run {
            result.error("INVALID_ARGUMENT", "sourcePath is required", null)
            return
        }
        val outputPath = call.argument<String>("outputPath") ?: run {
            result.error("INVALID_ARGUMENT", "outputPath is required", null)
            return
        }

        pluginScope.launch(Dispatchers.IO) {
            val res = renderEngine?.extractAudio(sourcePath, outputPath)
            withContext(Dispatchers.Main) {
                if (res is FFmpegRenderEngine.RenderResult.Success) {
                    result.success(res.outputPath)
                } else {
                    result.error("EXTRACTION_FAILED", "Failed to extract audio", null)
                }
            }
        }
    }

    private fun handleExtractFrame(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath") ?: run {
            result.error("INVALID_ARGUMENT", "sourcePath is required", null)
            return
        }
        val timeMs = (call.argument<Number>("timeMs"))?.toLong() ?: 0L
        val outputPath = call.argument<String>("outputPath") ?: run {
            result.error("INVALID_ARGUMENT", "outputPath is required", null)
            return
        }

        pluginScope.launch(Dispatchers.IO) {
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

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    private fun sendEvent(data: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(data)
        }
    }

    private fun saveToMediaStore(ctx: Context?, filePath: String) {
        if (ctx == null) return
        try {
            val file = File(filePath)
            if (!file.exists()) return

            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Video.Media.DISPLAY_NAME, file.name)
                put(android.provider.MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(android.provider.MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    put(android.provider.MediaStore.Video.Media.RELATIVE_PATH, "Movies/MotionBox")
                    put(android.provider.MediaStore.Video.Media.IS_PENDING, 1)
                }
            }

            val resolver = ctx.contentResolver
            val collection = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                android.provider.MediaStore.Video.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }

            val itemUri = resolver.insert(collection, values)
            if (itemUri != null) {
                resolver.openOutputStream(itemUri)?.use { out ->
                    file.inputStream().use { input ->
                        input.copyTo(out)
                    }
                }

                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(android.provider.MediaStore.Video.Media.IS_PENDING, 0)
                    resolver.update(itemUri, values, null, null)
                }
                Log.d(TAG, "Successfully exported video to MediaStore: $itemUri")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save video to MediaStore: ${e.message}", e)
        }
    }
}

