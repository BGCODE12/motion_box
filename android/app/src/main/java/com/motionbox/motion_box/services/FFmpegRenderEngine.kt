package com.motionbox.motion_box.services

import android.content.Context
import android.net.Uri
import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.FFmpegSession
import com.antonkarpenko.ffmpegkit.Level
import com.antonkarpenko.ffmpegkit.ReturnCode
import com.motionbox.motion_box.models.VideoProject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import java.io.File

class FFmpegRenderEngine(private val context: Context) {

    private val activeSessions = mutableListOf<FFmpegSession>()
    private val TAG = "FFmpegRenderEngine"

    init {
        val fontDir = listOf(
            "/system/fonts",
            "/system/font",
            "/data/fonts",
            "/product/fonts"
        ).firstOrNull { File(it).isDirectory } ?: "/system/fonts"

        try {
            FFmpegKitConfig.setFontDirectory(context, fontDir, null)
            Log.d(TAG, "Font directory set to: $fontDir")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set font directory '$fontDir': ${e.message}")
        }

        try {
            FFmpegKitConfig.enableLogCallback { log ->
                val msg = log.getMessage()?.trimEnd() ?: return@enableLogCallback
                if (msg.isEmpty()) return@enableLogCallback
                when (log.getLevel()) {
                    Level.AV_LOG_ERROR, Level.AV_LOG_FATAL, Level.AV_LOG_PANIC, Level.AV_LOG_STDERR
                        -> Log.e(TAG, "[ffmpeg] $msg")
                    Level.AV_LOG_WARNING
                        -> Log.w(TAG, "[ffmpeg] $msg")
                    else -> Log.v(TAG, "[ffmpeg] $msg")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not register FFmpegKit global log callback: ${e.message}")
        }
    }

    sealed class RenderResult {
        data class Success(val outputPath: String, val session: FFmpegSession) : RenderResult()
        data class Failure(val error: String, val session: FFmpegSession? = null) : RenderResult()
        object Cancelled : RenderResult()
    }

    fun copyFontToCache(assetPath: String = "fonts/Roboto-Regular.ttf"): String? {
        return try {
            val fileName = assetPath.substringAfterLast('/')
            val fontFile = File(context.cacheDir, fileName)
            if (!fontFile.exists()) {
                try {
                    context.assets.open(assetPath).use { input ->
                        fontFile.outputStream().use { input.copyTo(it) }
                    }
                    Log.d(TAG, "Font copied to cache: ${fontFile.absolutePath}")
                } catch (assetEx: Exception) {
                    Log.w(TAG, "Font asset '$assetPath' not found in APK assets (${assetEx.message}) — text overlay will use FFmpeg default font.")
                    return null
                }
            }

            val fontMap = mutableMapOf<String, String>()
            val alias = fileName.substringBeforeLast('.')
            fontMap[alias] = fileName
            FFmpegKitConfig.setFontDirectory(context, context.cacheDir.absolutePath, fontMap)
            fontFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy font to cache: ${e.message}", e)
            null
        }
    }

    suspend fun executeCommand(command: String): RenderResult {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Executing FFmpeg command: $command")
                val session = FFmpegKit.execute(command)
                activeSessions.add(session)

                val returnCode = session.getReturnCode()
                Log.d(TAG, "FFmpeg completed with return code: $returnCode")

                if (ReturnCode.isSuccess(returnCode)) {
                    RenderResult.Success(
                        outputPath = extractOutputPath(command),
                        session = session
                    )
                } else {
                    val failLog = session.getFailStackTrace()?.takeIf { it.isNotBlank() }
                        ?: session.getAllLogsAsString()?.takeIf { it.isNotBlank() }
                        ?: "FFmpeg exited with code ${returnCode?.getValue()}"

                    if (command.contains("h264_mediacodec")) {
                        Log.w(TAG, "Hardware encoder h264_mediacodec failed. Falling back to software encoder libx264.")
                        val fallbackCommand = command.replace("h264_mediacodec", "libx264")
                        return@withContext executeCommand(fallbackCommand)
                    }

                    Log.e(TAG, "FFmpeg error: $failLog")
                    RenderResult.Failure(error = failLog, session = session)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception during FFmpeg execution: ${e.message}", e)
                RenderResult.Failure(error = e.message ?: "Unknown exception")
            }
        }
    }

    suspend fun renderProject(
        project: VideoProject,
        sourceFilePath: String,
        outputFilePath: String,
        exportResolution: Int = 1080,
        exportFps: Int = 30,
        exportAudioOnly: Boolean = false,
        fontFilePath: String? = null,
        onProgress: ((Int) -> Unit)? = null
    ): RenderResult {
        val engine = LibreCutsEngine()
        val command = engine.buildConsolidatedFFmpegCommand(
            project = project,
            sourceFilePath = sourceFilePath,
            outputFilePath = outputFilePath,
            exportResolution = exportResolution,
            exportFps = exportFps,
            exportAudioOnly = exportAudioOnly,
            fontFilePath = fontFilePath,
            context = context
        ) ?: return RenderResult.Failure("Failed to synthesize FFmpeg command from VideoProject")

        val totalDurationSecs = project.getDurationAfterTrims()?.let { it / 1000.0 }
        return exportFinal(command, totalDurationSecs, onProgress)
    }

    suspend fun exportFinal(
        ffmpegCommand: String,
        totalDurationSecs: Double? = null,
        onProgress: ((Int) -> Unit)? = null
    ): RenderResult {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Executing FFmpeg command: $ffmpegCommand")

                val session = suspendCancellableCoroutine<FFmpegSession> { cont ->
                    val asyncSession = FFmpegKit.executeAsync(ffmpegCommand, { completeSession ->
                        cont.resume(completeSession)
                    }, { log ->
                        val msg = log.message?.trimEnd() ?: return@executeAsync
                        if (msg.isNotEmpty()) Log.d(TAG, "[ffmpeg] $msg")
                    }, { statistics ->
                        if (totalDurationSecs != null && totalDurationSecs > 0) {
                            val timeMs = statistics.time
                            if (timeMs > 0) {
                                val timeSecs = timeMs.toDouble() / 1000.0
                                val progress = (timeSecs / totalDurationSecs * 100).toInt()
                                onProgress?.invoke(progress.coerceIn(0, 100))
                            }
                        }
                    })
                    activeSessions.add(asyncSession)

                    cont.invokeOnCancellation {
                        FFmpegKit.cancel(asyncSession.sessionId)
                        activeSessions.remove(asyncSession)
                    }
                }

                activeSessions.remove(session)
                val returnCode = session.getReturnCode()

                if (ReturnCode.isSuccess(returnCode)) {
                    RenderResult.Success(
                        outputPath = extractOutputPath(ffmpegCommand),
                        session = session
                    )
                } else {
                    val failLog = session.getFailStackTrace()?.takeIf { it.isNotBlank() }
                        ?: session.getAllLogsAsString()?.takeIf { it.isNotBlank() }
                        ?: "FFmpeg exited with code ${returnCode?.getValue()}"

                    if (ffmpegCommand.contains("h264_mediacodec")) {
                        Log.w(TAG, "Hardware encoder h264_mediacodec failed. Falling back to software encoder libx264.")
                        val fallbackCommand = ffmpegCommand.replace("h264_mediacodec", "libx264")
                        return@withContext exportFinal(fallbackCommand, totalDurationSecs, onProgress)
                    }

                    Log.e(TAG, "FFmpeg error: $failLog")
                    RenderResult.Failure(error = failLog, session = session)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception during FFmpeg execution: ${e.message}", e)
                RenderResult.Failure(error = e.message ?: "Unknown exception")
            }
        }
    }

    suspend fun cancelAllSessions() {
        withContext(Dispatchers.IO) {
            FFmpegKit.cancel()
            activeSessions.clear()
        }
    }

    suspend fun extractAudio(sourceFilePath: String, outputFilePath: String): RenderResult {
        val command = "-y -i \"$sourceFilePath\" -vn -acodec copy \"$outputFilePath\""
        return executeCommand(command)
    }

    suspend fun extractFrame(sourceFilePath: String, timeMs: Long, outputImagePath: String): RenderResult {
        val actualSourcePath = if (sourceFilePath.startsWith("content://")) {
            val uri = Uri.parse(sourceFilePath)
            val tempFile = File.createTempFile("temp_frame_src", ".mp4", context.cacheDir)
            context.contentResolver.openInputStream(uri)?.use { input ->
                tempFile.outputStream().use { input.copyTo(it) }
            }
            tempFile.absolutePath
        } else {
            sourceFilePath
        }

        val timeSecs = timeMs / 1000.0
        val command = "-y -ss $timeSecs -i \"$actualSourcePath\" -vframes 1 -vf \"scale=160:-2\" \"$outputImagePath\""
        return executeCommand(command)
    }


    fun cleanup() {
        activeSessions.clear()
    }

    private fun extractOutputPath(command: String): String {
        val quotedRegex = """"([^"]*)"\s*$""".toRegex()
        quotedRegex.find(command)?.groupValues?.get(1)?.let { return it }
        return command.trimEnd().split("\\s+".toRegex()).lastOrNull() ?: ""
    }
}
