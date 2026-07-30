package com.motionbox.motion_box.models

import android.net.Uri
import com.google.gson.annotations.SerializedName
import java.io.Serializable

sealed class EditOperation : Serializable {

    data class Trim(
        val startMs: Long,
        val endMs: Long,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        init {
            require(startMs >= 0) { "Start time cannot be negative" }
            require(endMs > startMs) { "End time must be greater than start time" }
        }
    }

    data class SpeedMain(
        val speed: Float,
        val proxyUri: Uri? = null,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class ReverseMain(
        val isReversed: Boolean,
        val proxyUri: Uri? = null,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class MirrorMain(
        val isMirrored: Boolean,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class Crop(
        val aspectRatio: String,
        val xFraction: Float = 0f,
        val yFraction: Float = 0f,
        val wFraction: Float = 1f,
        val hFraction: Float = 1f,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        init {
            require(aspectRatio in listOf("16:9", "9:16", "1:1", "Custom")) {
                "Unsupported aspect ratio: $aspectRatio"
            }
        }
    }

    data class KeyframePoint(
        val timeMs: Long,
        val valueX: Float,
        val valueY: Float = 0f,
        val interpolationType: String = "linear"
    ) : Serializable

    data class AddText(
        val text: String,
        val fontSize: Int,
        val position: TextPosition,
        val relativeX: Float? = null,
        val relativeY: Float? = null,
        val color: String = "#FFFFFF",
        val startTimeMs: Long? = null,
        val endTimeMs: Long? = null,
        val id: String = System.nanoTime().toString(),
        val fontPath: String? = null,
        val opacity: Float = 1.0f,
        val borderThickness: Int = 0,
        val borderColor: String = "#000000",
        val textAlign: String = "center",
        val letterSpacing: Float = 0f,
        val lineSpacing: Float = 0f,
        val positionKeyframes: List<KeyframePoint> = emptyList(),
        val opacityKeyframes: List<KeyframePoint> = emptyList()
    ) : EditOperation() {
        init {
            require(text.isNotEmpty()) { "Text cannot be empty" }
            require(fontSize > 0) { "Font size must be positive" }
            relativeX?.let { require(it in 0f..1f) { "relativeX must be in 0.0..1.0" } }
            relativeY?.let { require(it in 0f..1f) { "relativeY must be in 0.0..1.0" } }
            require(opacity in 0f..1f) { "opacity must be in 0.0..1.0" }
        }

        fun hasCustomPosition(): Boolean = relativeX != null && relativeY != null
    }

    enum class MaskShape { NONE, SPLIT, SHUTTER, ELLIPSE, RECTANGLE }

    data class MaskConfig(
        val shape: MaskShape = MaskShape.NONE,
        val relativeX: Float = 0.5f,
        val relativeY: Float = 0.5f,
        val relativeWidth: Float = 0.5f,
        val relativeHeight: Float = 0.5f,
        val rotationAngle: Float = 0f,
        val isInverted: Boolean = false
    ) : Serializable

    data class MergeItem(
        val uri: Uri,
        val durationMs: Long,
        val trimStartMs: Long = 0L,
        val trimEndMs: Long = durationMs,
        val speed: Float = 1.0f,
        val proxyUri: Uri? = null,
        val isReversed: Boolean = false,
        val isMirrored: Boolean = false,
        val maskConfig: MaskConfig = MaskConfig()
    ) : Serializable {
        val trimmedDurationMs: Long
            get() = ((trimEndMs - trimStartMs) / speed).toLong()
    }

    data class Merge(
        val items: List<MergeItem>,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        init {
            require(items.isNotEmpty()) { "Must provide at least one video to merge" }
        }
        val videoUris: List<Uri> get() = items.map { it.uri }
    }

    data class MaskMain(
        val maskConfig: MaskConfig,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class MuteAudio(
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class Transition(
        val index: Int,
        @SerializedName("transitionType") val type: String,
        val durationMs: Long = 1000L,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class MuteClip(
        val index: Int,
        val isMuted: Boolean,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class ColorFilter(
        val index: Int,
        val filterName: String,
        val id: String = System.nanoTime().toString()
    ) : EditOperation()

    data class AddBackgroundAudio(
        val audioUri: Uri,
        val removeOriginalAudio: Boolean = false,
        val volume: Float = 1.0f,
        val internalStartMs: Long = 0L,
        val internalEndMs: Long = -1L,
        val startTimeMs: Long? = null,
        val endTimeMs: Long? = null,
        val originalDurationMs: Long = 0L,
        val extractedFromSegmentIndex: Int? = null,
        val beats: List<Long> = emptyList(),
        val ducking: Boolean = false,
        val fadeInDurationMs: Long = 0L,
        val fadeOutDurationMs: Long = 0L,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        init {
            require(volume in 0f..2f) { "Volume must be in 0.0..2.0" }
            require(internalStartMs >= 0) { "Internal start time cannot be negative" }
        }
    }

    data class AddImageOverlay(
        val imageUri: Uri,
        val relativeX: Float,
        val relativeY: Float,
        val relativeWidth: Float,
        val relativeHeight: Float,
        val rotationAngle: Float,
        val startTimeMs: Long? = null,
        val endTimeMs: Long? = null,
        val id: String = System.nanoTime().toString(),
        val fileDurationMs: Long? = null,
        val isLooping: Boolean = true,
        val chromaKeyColor: String? = null,
        val chromaKeySimilarity: Float = 0.1f,
        val opacity: Float = 1.0f,
        val isMirrored: Boolean = false,
        val positionKeyframes: List<KeyframePoint> = emptyList(),
        val opacityKeyframes: List<KeyframePoint> = emptyList(),
        val speedKeyframes: List<KeyframePoint> = emptyList(),
        val maskConfig: MaskConfig = MaskConfig()
    ) : EditOperation()

    data class AddSubtitles(
        val subtitlesUri: Uri,
        val srtContent: String,
        val fileName: String,
        val cues: List<SubtitleCue>,
        val color: String = "#FFFFFF",
        val backgroundColor: String = "none",
        val fontSize: Int = 22,
        val position: TextPosition = TextPosition.BOTTOM_CENTER,
        val relativeX: Float? = null,
        val relativeY: Float? = null,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        fun hasCustomPosition(): Boolean = relativeX != null && relativeY != null
    }

    data class Adjust(
        val index: Int,
        val brightness: Int = 0,
        val contrast: Int = 0,
        val warmth: Int = 0,
        val shadow: Int = 0,
        val highlights: Int = 0,
        val saturation: Int = 0,
        val exposure: Int = 0,
        val sharpen: Int = 0,
        val vignette: Int = 0,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        fun isDefault(): Boolean {
            return brightness == 0 && contrast == 0 && warmth == 0 &&
                   shadow == 0 && highlights == 0 && saturation == 0 &&
                   exposure == 0 && sharpen == 0 && vignette == 0
        }
    }

    data class CanvasBackground(
        @SerializedName("backgroundType") val type: BackgroundType = BackgroundType.COLOR,
        val colorHex: String = "#000000",
        val imageUri: Uri? = null,
        val blurRadius: Int = 20,
        val id: String = System.nanoTime().toString()
    ) : EditOperation() {
        enum class BackgroundType { COLOR, IMAGE, BLUR }
    }
}

data class SubtitleCue(
    val startTimeMs: Long,
    val endTimeMs: Long,
    val text: String
) : Serializable

enum class TextPosition(val ffmpegParam: String) : Serializable {
    BOTTOM_RIGHT("x=w-tw:y=h-th"),
    TOP_RIGHT("x=w-tw:y=0"),
    TOP_LEFT("x=0:y=0"),
    BOTTOM_LEFT("x=0:y=h-th"),
    CENTER_BOTTOM("x=(w-text_w)/2:y=h-th"),
    CENTER_TOP("x=(w-text_w)/2:y=0"),
    CENTER("x=(w-text_w)/2:y=(h-text_h)/2"),
    TOP_CENTER("x=(w-text_w)/2:y=0"),
    CENTER_LEFT("x=0:y=(h-text_h)/2"),
    CENTER_RIGHT("x=w-tw:y=(h-text_h)/2"),
    BOTTOM_CENTER("x=(w-text_w)/2:y=h-th");

    companion object {
        fun fromLabel(label: String): TextPosition = when (label) {
            "Bottom Right" -> BOTTOM_RIGHT
            "Top Right" -> TOP_RIGHT
            "Top Left" -> TOP_LEFT
            "Bottom Left" -> BOTTOM_LEFT
            "Center Bottom" -> CENTER_BOTTOM
            "Center Top" -> CENTER_TOP
            "Center Align" -> CENTER
            "Top Center" -> TOP_CENTER
            "Center Left" -> CENTER_LEFT
            "Center Right" -> CENTER_RIGHT
            "Bottom Center" -> BOTTOM_CENTER
            else -> CENTER
        }
    }
}

val EditOperation.id: String
    get() = when (this) {
        is EditOperation.Trim -> id
        is EditOperation.SpeedMain -> id
        is EditOperation.ReverseMain -> id
        is EditOperation.MirrorMain -> id
        is EditOperation.MaskMain -> id
        is EditOperation.Crop -> id
        is EditOperation.AddText -> id
        is EditOperation.Merge -> id
        is EditOperation.MuteAudio -> id
        is EditOperation.Transition -> id
        is EditOperation.MuteClip -> id
        is EditOperation.ColorFilter -> id
        is EditOperation.AddBackgroundAudio -> id
        is EditOperation.AddImageOverlay -> id
        is EditOperation.AddSubtitles -> id
        is EditOperation.Adjust -> id
        is EditOperation.CanvasBackground -> id
    }
