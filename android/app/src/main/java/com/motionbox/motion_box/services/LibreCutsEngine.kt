package com.motionbox.motion_box.services

import android.content.Context
import android.net.Uri
import android.util.Log
import com.motionbox.motion_box.models.EditOperation
import com.motionbox.motion_box.models.TextPosition
import com.motionbox.motion_box.models.VideoProject
import java.io.File
import java.io.FileOutputStream

/**
 * Headless Video Editing Engine for MotionBox.
 *
 * Synthesizes single-pass -filter_complex FFmpeg commands from VideoProject state.
 * Has ZERO dependencies on ViewModels or UI components.
 */
class LibreCutsEngine {

    companion object {
        private const val TAG = "LibreCutsEngine"
    }

    fun buildConsolidatedFFmpegCommand(
        project: VideoProject,
        sourceFilePath: String,
        outputFilePath: String,
        exportResolution: Int = 1080,
        exportFps: Int = 30,
        exportAudioOnly: Boolean = false,
        fontFilePath: String? = null,
        context: Context? = null
    ): String? {
        if (project.operations.isEmpty()) {
            return "-y -i \"$sourceFilePath\" -c copy \"$outputFilePath\""
        }

        val density = context?.resources?.displayMetrics?.density ?: 1.0f
        val operations = project.operations

        val hasAudio = try {
            val retriever = android.media.MediaMetadataRetriever()
            try {
                retriever.setDataSource(sourceFilePath)
                val hasAudioStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
                hasAudioStr == "yes"
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking audio in source file: ${e.message}")
            true
        }

        val mergeOp = operations.filterIsInstance<EditOperation.Merge>().firstOrNull()
        val nonMergeOps = operations.filterNot { it is EditOperation.Merge }
        val trimOp = operations.filterIsInstance<EditOperation.Trim>().lastOrNull()
        val audioOps = operations.filterIsInstance<EditOperation.AddBackgroundAudio>()
        val audioMuted = operations.any { it is EditOperation.MuteAudio }
        val videoOps = nonMergeOps.filter {
            it is EditOperation.Crop || it is EditOperation.AddText ||
            it is EditOperation.AddImageOverlay || it is EditOperation.AddSubtitles
        }
        val imageOps = operations.filterIsInstance<EditOperation.AddImageOverlay>()

        val cmd = StringBuilder("-y")
        var inputIndex = 0

        fun resolveUriToPath(uri: Uri): String? {
            if (uri.scheme == "content" && context != null) {
                return copyContentUriToTempFile(context, uri)
            }
            return uri.path ?: uri.toString()
        }

        var outputDuration: Double? = null
        val reverseOp = operations.filterIsInstance<EditOperation.ReverseMain>().lastOrNull()
        val speedOp = operations.filterIsInstance<EditOperation.SpeedMain>().lastOrNull()
        val finalProxyUri = reverseOp?.proxyUri ?: speedOp?.proxyUri

        if (finalProxyUri != null) {
            val proxyPath = resolveUriToPath(finalProxyUri) ?: finalProxyUri.toString()
            val baseDuration = if (trimOp != null) (trimOp.endMs - trimOp.startMs) else 0L
            if (baseDuration > 0) {
                val speed = speedOp?.speed ?: 1.0f
                outputDuration = baseDuration / speed / 1000.0
                cmd.append(" -t $outputDuration -i \"$proxyPath\"")
            } else {
                cmd.append(" -i \"$proxyPath\"")
            }
        } else if (trimOp != null) {
            val startSecs = trimOp.startMs / 1000.0
            val duration = (trimOp.endMs - trimOp.startMs) / 1000.0
            if (mergeOp == null) {
                outputDuration = duration
            }
            cmd.append(" -ss $startSecs -t $duration -i \"$sourceFilePath\"")
        } else {
            cmd.append(" -i \"$sourceFilePath\"")
        }
        inputIndex++

        val mergeVideoIndices = mutableListOf<Int>()
        if (mergeOp != null) {
            for (item in mergeOp.items) {
                if (item.proxyUri != null) {
                    val proxyPath = item.proxyUri.path ?: item.proxyUri.toString()
                    val duration = item.trimmedDurationMs / 1000.0
                    cmd.append(" -t $duration -i \"$proxyPath\"")
                } else {
                    val videoPath = resolveUriToPath(item.uri) ?: item.uri.toString()
                    val startSecs = item.trimStartMs / 1000.0
                    val duration = (item.trimEndMs - item.trimStartMs) / 1000.0

                    val isImage = videoPath.endsWith(".png", ignoreCase = true) ||
                                  videoPath.endsWith(".jpg", ignoreCase = true) ||
                                  videoPath.endsWith(".jpeg", ignoreCase = true) ||
                                  videoPath.endsWith(".webp", ignoreCase = true)

                    if (isImage) {
                        cmd.append(" -loop 1 -t $duration -i \"$videoPath\"")
                    } else {
                        cmd.append(" -ss $startSecs -t $duration -i \"$videoPath\"")
                    }
                }
                mergeVideoIndices.add(inputIndex)
                inputIndex++
            }
        }

        val audioInputIndices = mutableListOf<Pair<Int, EditOperation.AddBackgroundAudio>>()
        for (audioOp in audioOps) {
            val audioPath = resolveUriToPath(audioOp.audioUri)
            if (audioPath == null) {
                Log.e(TAG, "Failed to resolve audio URI to path: ${audioOp.audioUri} — skipping track")
                continue
            }
            cmd.append(" -i \"$audioPath\"")
            audioInputIndices.add(Pair(inputIndex, audioOp))
            inputIndex++
        }

        val imageInputIndices = mutableListOf<Pair<Int, EditOperation.AddImageOverlay>>()
        for (imageOp in imageOps) {
            val imagePath = resolveUriToPath(imageOp.imageUri)
            if (imagePath == null) {
                Log.e(TAG, "Failed to resolve image URI to path: ${imageOp.imageUri} — skipping overlay")
                continue
            }
            val isGif = imagePath.endsWith(".gif", ignoreCase = true)
            val isVideo = imagePath.endsWith(".mp4", ignoreCase = true) ||
                          imagePath.endsWith(".mkv", ignoreCase = true) ||
                          imagePath.endsWith(".mov", ignoreCase = true) ||
                          imagePath.endsWith(".3gp", ignoreCase = true)
            if ((isGif || isVideo) && imageOp.isLooping) {
                cmd.append(" -stream_loop -1 -i \"$imagePath\"")
            } else {
                cmd.append(" -i \"$imagePath\"")
            }
            imageInputIndices.add(Pair(inputIndex, imageOp))
            inputIndex++
        }

        val bgOp = operations.filterIsInstance<EditOperation.CanvasBackground>().lastOrNull()
        var bgImageIndex = -1
        if (bgOp != null && bgOp.type == EditOperation.CanvasBackground.BackgroundType.IMAGE && bgOp.imageUri != null) {
            val bgPath = resolveUriToPath(bgOp.imageUri)
            if (bgPath != null) {
                cmd.append(" -loop 1 -i \"$bgPath\"")
                bgImageIndex = inputIndex
                inputIndex++
            }
        }

        // ── MERGE PATH ────────────────────────────────────────────────────────
        if (mergeOp != null) {
            val inputCount = 1 + mergeOp.items.size
            val filterParts = mutableListOf<String>()

            var mainWidth = 1280
            var mainHeight = 720
            var sourceDurationMs = 0L
            try {
                val retriever = android.media.MediaMetadataRetriever()
                try {
                    retriever.setDataSource(sourceFilePath)
                    val wStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    val hStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    val rStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    val dStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                    val w = wStr?.toIntOrNull() ?: 1280
                    val h = hStr?.toIntOrNull() ?: 720
                    val r = rStr?.toIntOrNull() ?: 0
                    sourceDurationMs = dStr?.toLongOrNull() ?: 0L
                    if (r == 90 || r == 270) {
                        mainWidth = h
                        mainHeight = w
                    } else {
                        mainWidth = w
                        mainHeight = h
                    }
                } finally {
                    retriever.release()
                }
                if (mainWidth % 2 != 0) mainWidth -= 1
                if (mainHeight % 2 != 0) mainHeight -= 1
            } catch (e: Exception) {
                Log.e(TAG, "Error extracting dimensions: ${e.message}")
            }

            val hasAudioArray = BooleanArray(inputCount)
            val durationsArray = DoubleArray(inputCount)

            hasAudioArray[0] = hasAudio
            durationsArray[0] = if (speedOp?.proxyUri != null) {
                val base = if (trimOp != null) (trimOp.endMs - trimOp.startMs) else sourceDurationMs
                (base / speedOp.speed) / 1000.0
            } else if (trimOp != null) {
                (trimOp.endMs - trimOp.startMs) / 1000.0
            } else {
                sourceDurationMs / 1000.0
            }

            for ((idx, item) in mergeOp.items.withIndex()) {
                val path = item.uri.path ?: item.uri.toString()
                hasAudioArray[idx + 1] = try {
                    val isImage = path.endsWith(".png", ignoreCase = true) ||
                                  path.endsWith(".jpg", ignoreCase = true) ||
                                  path.endsWith(".jpeg", ignoreCase = true) ||
                                  path.endsWith(".webp", ignoreCase = true)
                    if (isImage) {
                        false
                    } else {
                        val r = android.media.MediaMetadataRetriever()
                        try {
                            r.setDataSource(path)
                            val hStr = r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
                            hStr == "yes"
                        } finally {
                            r.release()
                        }
                    }
                } catch (e: Exception) { false }
                durationsArray[idx + 1] = item.trimmedDurationMs / 1000.0
            }

            for (i in 0 until inputCount) {
                val colorFilterOp = operations.filterIsInstance<EditOperation.ColorFilter>().find { it.index == i }
                val lutFilterExpr = colorFilterOp?.let { getFFmpegFilterForName(it.filterName) }
                val adjustOp = operations.filterIsInstance<EditOperation.Adjust>().find { it.index == i }
                val adjustFilterExpr = adjustOp?.let { getFFmpegFilterForAdjust(it) }

                val isMirrored = if (i == 0) {
                    operations.any { it is EditOperation.MirrorMain && it.isMirrored }
                } else {
                    mergeOp.items.getOrNull(i - 1)?.isMirrored == true
                }

                val maskConfig = if (i == 0) {
                    operations.filterIsInstance<EditOperation.MaskMain>().lastOrNull()?.maskConfig ?: EditOperation.MaskConfig()
                } else {
                    mergeOp.items.getOrNull(i - 1)?.maskConfig ?: EditOperation.MaskConfig()
                }

                var preFilters = "setpts=PTS-STARTPTS"
                if (lutFilterExpr != null) preFilters += ",$lutFilterExpr"
                if (adjustFilterExpr != null) preFilters += ",$adjustFilterExpr"
                if (isMirrored) preFilters += ",hflip"

                if (maskConfig.shape != EditOperation.MaskShape.NONE) {
                    val mc = maskConfig
                    val cx = "W*${mc.relativeX}"
                    val cy = "H*${mc.relativeY}"
                    val mw = "W*${mc.relativeWidth}"
                    val mh = "H*${mc.relativeHeight}"
                    val rad = Math.toRadians(mc.rotationAngle.toDouble())
                    val cosA = Math.cos(rad)
                    val sinA = Math.sin(rad)
                    val dx = "(X - $cx)"
                    val dy = "(Y - $cy)"
                    val rx = "($dx * $cosA - $dy * $sinA)"
                    val ry = "($dx * $sinA + $dy * $cosA)"

                    val shapeExpr = when (mc.shape) {
                        EditOperation.MaskShape.RECTANGLE -> "if(lt(abs($rx), $mw/2) * lt(abs($ry), $mh/2), 255, 0)"
                        EditOperation.MaskShape.ELLIPSE -> "if(lte(pow($rx/($mw/2), 2) + pow($ry/($mh/2), 2), 1), 255, 0)"
                        EditOperation.MaskShape.SPLIT -> "if(gt($ry, 0), 255, 0)"
                        EditOperation.MaskShape.SHUTTER -> "if(lt(abs($ry), $mh/2), 255, 0)"
                        else -> "255"
                    }
                    val finalAlphaExpr = if (mc.isInverted) "(255 - ($shapeExpr))" else "($shapeExpr)"
                    preFilters += ",format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*($finalAlphaExpr/255)'"
                }

                filterParts.add("[$i:v]$preFilters[pre$i]")

                if (bgOp?.type == EditOperation.CanvasBackground.BackgroundType.BLUR) {
                    val blur = bgOp.blurRadius
                    val bgScale = "format=yuv420p,scale=$mainWidth:$mainHeight:force_original_aspect_ratio=increase,crop=$mainWidth:$mainHeight,boxblur=$blur"
                    val fgScale = "scale=$mainWidth:$mainHeight:force_original_aspect_ratio=decrease"
                    filterParts.add("[pre$i]split=2[bg_orig$i][fg_orig$i]")
                    filterParts.add("[bg_orig$i]$bgScale[bg$i]")
                    filterParts.add("[fg_orig$i]$fgScale[fg$i]")
                    filterParts.add("[bg$i][fg$i]overlay=(W-w)/2:(H-h)/2,setsar=1,fps=30,format=yuv420p[norm$i]")
                } else if (bgOp?.type == EditOperation.CanvasBackground.BackgroundType.IMAGE && bgImageIndex != -1) {
                    val bgScale = "scale=$mainWidth:$mainHeight:force_original_aspect_ratio=increase,crop=$mainWidth:$mainHeight"
                    val fgScale = "scale=$mainWidth:$mainHeight:force_original_aspect_ratio=decrease"
                    filterParts.add("[$bgImageIndex:v]$bgScale[bg$i]")
                    filterParts.add("[pre$i]$fgScale[fg$i]")
                    filterParts.add("[bg$i][fg$i]overlay=(W-w)/2:(H-h)/2:shortest=1,setsar=1,fps=30,format=yuv420p[norm$i]")
                } else {
                    val color = bgOp?.colorHex ?: "black"
                    val padColor = if (color.startsWith("#")) color else "black"
                    filterParts.add("color=c=$padColor:s=${mainWidth}x${mainHeight}:r=30[bg$i]")
                    filterParts.add("[pre$i]scale=$mainWidth:$mainHeight:force_original_aspect_ratio=decrease[fg$i]")
                    filterParts.add("[bg$i][fg$i]overlay=(W-w)/2:(H-h)/2:shortest=1,setsar=1,fps=30,format=yuv420p[norm$i]")
                }

                val isClipMuted = operations.filterIsInstance<EditOperation.MuteClip>().find { it.index == i }?.isMuted ?: false
                if (hasAudioArray[i] && !isClipMuted) {
                    filterParts.add("[$i:a]asetpts=PTS-STARTPTS,aformat=sample_rates=44100:channel_layouts=stereo[anorm$i]")
                } else {
                    val d = durationsArray[i]
                    filterParts.add("anullsrc=r=44100:cl=stereo,atrim=duration=$d,asetpts=PTS-STARTPTS[anorm$i]")
                }
            }

            val transitionOps = List(inputCount - 1) { gapIdx ->
                operations.filterIsInstance<EditOperation.Transition>().find { it.index == gapIdx }
            }

            data class StreamInfo(val vLabel: String, val aLabel: String, val durationSec: Double)

            val pendingClipIndices = mutableListOf(0)
            var currentStream: StreamInfo? = null
            var transitionLabelCounter = 0
            var concatLabelCounter = 0

            fun flushPendingGroup(clipIndices: List<Int>): StreamInfo {
                return if (clipIndices.size == 1) {
                    val i = clipIndices[0]
                    StreamInfo("[norm$i]", "[anorm$i]", durationsArray[i])
                } else {
                    val vOut = "[ccat${concatLabelCounter}v]"
                    val aOut = "[ccat${concatLabelCounter}a]"
                    val inputs = clipIndices.joinToString("") { "[norm$it][anorm$it]" }
                    filterParts.add("${inputs}concat=n=${clipIndices.size}:v=1:a=1${vOut}${aOut}")
                    filterParts.add("${vOut}settb=1/30,setpts=N[norm${concatLabelCounter}v]")
                    filterParts.add("${aOut}asetpts=PTS-STARTPTS[anorm${concatLabelCounter}a]")
                    val totalDur = clipIndices.sumOf { durationsArray[it] }
                    concatLabelCounter++
                    StreamInfo("[norm${concatLabelCounter - 1}v]", "[anorm${concatLabelCounter - 1}a]", totalDur)
                }
            }

            for (gapIdx in 0 until inputCount - 1) {
                val transOp = transitionOps[gapIdx]
                if (transOp == null || transOp.type == "none") {
                    pendingClipIndices.add(gapIdx + 1)
                } else {
                    val baseStream = if (pendingClipIndices.isEmpty()) {
                        currentStream ?: throw IllegalStateException("Both pending clips and currentStream are empty")
                    } else {
                        val leftStream = flushPendingGroup(pendingClipIndices)
                        pendingClipIndices.clear()
                        if (currentStream == null) {
                            leftStream
                        } else {
                            val vOut = "[ccat${concatLabelCounter}v]"
                            val aOut = "[ccat${concatLabelCounter}a]"
                            filterParts.add("${currentStream.vLabel}${currentStream.aLabel}${leftStream.vLabel}${leftStream.aLabel}concat=n=2:v=1:a=1${vOut}${aOut}")
                            filterParts.add("${vOut}settb=1/30,setpts=N[norm${concatLabelCounter}v]")
                            filterParts.add("${aOut}asetpts=PTS-STARTPTS[anorm${concatLabelCounter}a]")
                            concatLabelCounter++
                            StreamInfo("[norm${concatLabelCounter - 1}v]", "[anorm${concatLabelCounter - 1}a]", currentStream.durationSec + leftStream.durationSec)
                        }
                    }

                    val rawTransDuration = transOp.durationMs / 1000.0
                    val transDuration = rawTransDuration.coerceAtMost(baseStream.durationSec).coerceAtMost(durationsArray[gapIdx + 1])
                    val offset = (baseStream.durationSec - transDuration).coerceAtLeast(0.0)

                    val xfvOut = "[xfv${transitionLabelCounter}]"
                    val xfaOut = "[xfa${transitionLabelCounter}]"
                    val nextVLabel = "[norm${gapIdx + 1}]"
                    val nextALabel = "[anorm${gapIdx + 1}]"

                    val validXfadeTransitions = setOf(
                        "fade", "fadeblack", "fadewhite", "rectcrop", "circlecrop", "circleclose", "circleopen",
                        "horzclose", "horzopen", "vertclose", "vertopen", "diagbl", "diagbr", "diagtl", "diagtr",
                        "hlslice", "hrslice", "vuslice", "vdslice", "dissolve", "pixelize", "slidedown", "slideleft",
                        "slideright", "slideup", "wipedown", "wipeleft", "wiperight", "wipeup", "zoomin", "squeezeh",
                        "squeezev", "coverleft", "coverright", "coverup", "coverdown", "revealleft", "revealright",
                        "revealup", "revealdown"
                    )
                    val rawType = transOp.type.lowercase()
                    val sanitizedTransType = when (rawType) {
                        "smoothleft" -> "coverleft"
                        "smoothright" -> "coverright"
                        "distance" -> "zoomin"
                        else -> if (validXfadeTransitions.contains(rawType)) rawType else "fade"
                    }

                    filterParts.add("${baseStream.vLabel}${nextVLabel}xfade=transition=${sanitizedTransType}:duration=${transDuration}:offset=${offset}${xfvOut}")
                    filterParts.add("${baseStream.aLabel}${nextALabel}acrossfade=d=${transDuration}:c1=tri:c2=tri${xfaOut}")

                    val newDuration = offset + durationsArray[gapIdx + 1]
                    currentStream = StreamInfo(xfvOut, xfaOut, newDuration)
                    transitionLabelCounter++
                }
            }

            val remainingStream = if (pendingClipIndices.isNotEmpty()) flushPendingGroup(pendingClipIndices) else null

            val finalStream: StreamInfo = when {
                currentStream == null && remainingStream != null -> remainingStream
                currentStream != null && remainingStream == null -> currentStream!!
                currentStream != null && remainingStream != null -> {
                    val vOut = "[ccat${concatLabelCounter}v]"
                    val aOut = "[ccat${concatLabelCounter}a]"
                    filterParts.add("${currentStream.vLabel}${currentStream.aLabel}${remainingStream.vLabel}${remainingStream.aLabel}concat=n=2:v=1:a=1${vOut}${aOut}")
                    filterParts.add("${vOut}settb=1/30,setpts=N[norm${concatLabelCounter}v]")
                    filterParts.add("${aOut}asetpts=PTS-STARTPTS[anorm${concatLabelCounter}a]")
                    concatLabelCounter++
                    StreamInfo("[norm${concatLabelCounter - 1}v]", "[anorm${concatLabelCounter - 1}a]", currentStream.durationSec + remainingStream.durationSec)
                }
                else -> StreamInfo("[norm0]", "[anorm0]", durationsArray[0])
            }

            val currentVLabel = finalStream.vLabel
            var currentALabel = finalStream.aLabel
            val accumulatedDuration = finalStream.durationSec
            outputDuration = accumulatedDuration

            val (sourceVideoStages, tempVideoLabel) = buildVideoFilterStages(
                operations = videoOps,
                fontFilePath = fontFilePath,
                inputLabel = currentVLabel,
                imageInputIndices = imageInputIndices,
                density = density
            )
            filterParts.addAll(sourceVideoStages)
            val finalVideoLabel = "[fmtv]"
            filterParts.add("${tempVideoLabel}scale=-2:${exportResolution},fps=${exportFps},format=yuv420p$finalVideoLabel")

            if (audioMuted) {
                filterParts.add("${currentALabel}anullsink")
            } else if (audioInputIndices.isNotEmpty()) {
                val mixInputLabels = mutableListOf<String>()
                mixInputLabels.add(currentALabel)

                for ((idx, pair) in audioInputIndices.withIndex()) {
                    val (inputIdx, audioOp) = pair
                    val trackLabel = "[a_bg_$idx]"
                    val filters = mutableListOf<String>()

                    val internalStartSec = audioOp.internalStartMs / 1000.0
                    var internalEndSec = if (audioOp.internalEndMs > 0L) audioOp.internalEndMs / 1000.0 else Double.MAX_VALUE

                    if (audioOp.startTimeMs != null && audioOp.endTimeMs != null) {
                        val timelineDurationSec = (audioOp.endTimeMs - audioOp.startTimeMs) / 1000.0
                        val maxEndSec = internalStartSec + timelineDurationSec
                        if (maxEndSec < internalEndSec) internalEndSec = maxEndSec
                    }

                    if (internalStartSec > 0.0 || internalEndSec != Double.MAX_VALUE) {
                        if (internalEndSec != Double.MAX_VALUE) {
                            filters.add("atrim=start=$internalStartSec:end=$internalEndSec,asetpts=PTS-STARTPTS")
                        } else {
                            filters.add("atrim=start=$internalStartSec,asetpts=PTS-STARTPTS")
                        }
                    }
                    if (audioOp.fadeInDurationMs > 0L) {
                        val fadeSec = audioOp.fadeInDurationMs / 1000.0
                        filters.add("afade=t=in:st=0:d=$fadeSec")
                    }
                    if (audioOp.fadeOutDurationMs > 0L) {
                        val fadeSec = audioOp.fadeOutDurationMs / 1000.0
                        val clipDur = if (audioOp.endTimeMs != null && audioOp.startTimeMs != null) {
                            (audioOp.endTimeMs - audioOp.startTimeMs) / 1000.0
                        } else if (audioOp.internalEndMs > 0L) {
                            (audioOp.internalEndMs - audioOp.internalStartMs) / 1000.0
                        } else {
                            (audioOp.originalDurationMs - audioOp.internalStartMs) / 1000.0
                        }
                        val fadeOutStart = maxOf(0.0, clipDur - fadeSec)
                        filters.add("afade=t=out:st=$fadeOutStart:d=$fadeSec")
                    }
                    var delayMs = audioOp.startTimeMs ?: 0L
                    if (delayMs < 0) delayMs = 0L
                    if (delayMs > 0) {
                        filters.add("adelay=$delayMs|$delayMs")
                    }
                    if (audioOp.volume != 1.0f) {
                        filters.add("volume=${audioOp.volume}")
                    }

                    if (filters.isNotEmpty()) {
                        filterParts.add("[$inputIdx:a]${filters.joinToString(",")}$trackLabel")
                        mixInputLabels.add(trackLabel)
                    } else {
                        mixInputLabels.add("[$inputIdx:a]")
                    }
                }

                if (!audioInputIndices.any { it.second.removeOriginalAudio }) {
                    var mainAudioRef = currentALabel
                    val duckingCount = audioInputIndices.count { it.second.ducking }

                    if (duckingCount > 0) {
                        val splits = (0..duckingCount).map { "[main_split_$it]" }
                        filterParts.add("${mainAudioRef}asplit=${duckingCount + 1}${splits.joinToString("")}")
                        mainAudioRef = splits[0]

                        var splitIdx = 1
                        for (i in mixInputLabels.indices.drop(1)) {
                            val opIndex = i - 1
                            val op = audioInputIndices[opIndex].second
                            if (op.ducking) {
                                val bgLabel = mixInputLabels[i]
                                val sidechainLabel = splits[splitIdx++]
                                val duckedLabel = "[ducked_$opIndex]"
                                filterParts.add("${bgLabel}aformat=sample_rates=44100:channel_layouts=stereo[bg_fmt_$opIndex]")
                                filterParts.add("${sidechainLabel}aformat=sample_rates=44100:channel_layouts=stereo[sc_fmt_$opIndex]")
                                filterParts.add("[bg_fmt_$opIndex][sc_fmt_$opIndex]sidechaincompress=threshold=0.03:ratio=4:attack=5:release=500${duckedLabel}")
                                mixInputLabels[i] = duckedLabel
                            }
                        }
                    }

                    mixInputLabels[0] = mainAudioRef
                    val allInputs = mixInputLabels.joinToString("")
                    filterParts.add("${allInputs}amix=inputs=${mixInputLabels.size}:duration=longest[outa]")
                    currentALabel = "[outa]"
                } else {
                    filterParts.add("${mixInputLabels[0]}anullsink")
                    mixInputLabels.removeAt(0)
                    if (mixInputLabels.size == 1) {
                        val singleLabel = mixInputLabels[0]
                        filterParts.add("${singleLabel}aformat=sample_rates=44100:channel_layouts=stereo[outa]")
                        currentALabel = "[outa]"
                    } else {
                        val allBg = mixInputLabels.joinToString("")
                        filterParts.add("${allBg}amix=inputs=${mixInputLabels.size}:duration=longest[outa]")
                        currentALabel = "[outa]"
                    }
                }
            }

            if (exportAudioOnly) {
                filterParts.add("${finalVideoLabel}nullsink")
            }
            cmd.append(" -filter_complex \"${filterParts.joinToString(";")}\"")

            if (exportAudioOnly) {
                if (!audioMuted) {
                    cmd.append(" -map \"$currentALabel\"")
                    cmd.append(" -c:a libmp3lame -b:a 192k")
                } else {
                    cmd.append(" -an")
                }
            } else {
                cmd.append(" -map \"$finalVideoLabel\"")
                if (!audioMuted) {
                    cmd.append(" -map \"$currentALabel\"")
                } else {
                    cmd.append(" -an")
                }

                val bitrate = when (exportResolution) {
                    2160 -> "30M"
                    1440 -> "16M"
                    1080 -> "8M"
                    720 -> "5M"
                    480 -> "2M"
                    else -> "1M"
                }
                cmd.append(" -c:v h264_mediacodec -b:v $bitrate")

                if (!audioMuted) {
                    cmd.append(" -c:a aac")
                }
            }

            if (outputDuration != null) {
                cmd.append(" -t $outputDuration")
            }
            cmd.append(" \"$outputFilePath\"")

            val finalCommand = cmd.toString()
            Log.d(TAG, "Built merge command: $finalCommand")
            return finalCommand
        }

        // ── NON-MERGE PATH ────────────────────────────────────────────────────
        val filterComplexParts = mutableListOf<String>()
        var currentInputVideoLabel = "[0:v]"

        val colorFilterOp = operations.filterIsInstance<EditOperation.ColorFilter>().find { it.index == 0 }
        val adjustOp = operations.filterIsInstance<EditOperation.Adjust>().find { it.index == 0 }

        val prepFilters = mutableListOf<String>()
        if (colorFilterOp != null) {
            val lutFilterExpr = getFFmpegFilterForName(colorFilterOp.filterName)
            if (lutFilterExpr != null) {
                prepFilters.add(lutFilterExpr)
            }
        }
        if (adjustOp != null) {
            val adjustFilterExpr = getFFmpegFilterForAdjust(adjustOp)
            if (adjustFilterExpr != null) {
                prepFilters.add(adjustFilterExpr)
            }
        }
        val mirrorMainOp = operations.filterIsInstance<EditOperation.MirrorMain>().find { it.isMirrored }
        if (mirrorMainOp != null) {
            prepFilters.add("hflip")
        }

        val maskMainOp = operations.filterIsInstance<EditOperation.MaskMain>().lastOrNull()
        if (maskMainOp != null && maskMainOp.maskConfig.shape != EditOperation.MaskShape.NONE) {
            val mc = maskMainOp.maskConfig
            val cx = "W*${mc.relativeX}"
            val cy = "H*${mc.relativeY}"
            val mw = "W*${mc.relativeWidth}"
            val mh = "H*${mc.relativeHeight}"
            val rad = Math.toRadians(mc.rotationAngle.toDouble())
            val cosA = Math.cos(rad)
            val sinA = Math.sin(rad)
            val dx = "(X - $cx)"
            val dy = "(Y - $cy)"
            val rx = "($dx * $cosA - $dy * $sinA)"
            val ry = "($dx * $sinA + $dy * $cosA)"

            val shapeExpr = when (mc.shape) {
                EditOperation.MaskShape.RECTANGLE -> "if(lt(abs($rx), $mw/2) * lt(abs($ry), $mh/2), 255, 0)"
                EditOperation.MaskShape.ELLIPSE -> "if(lte(pow($rx/($mw/2), 2) + pow($ry/($mh/2), 2), 1), 255, 0)"
                EditOperation.MaskShape.SPLIT -> "if(gt($ry, 0), 255, 0)"
                EditOperation.MaskShape.SHUTTER -> "if(lt(abs($ry), $mh/2), 255, 0)"
                else -> "255"
            }
            val finalAlphaExpr = if (mc.isInverted) "(255 - ($shapeExpr))" else "($shapeExpr)"
            prepFilters.add("format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*($finalAlphaExpr/255)'")
        }

        if (prepFilters.isNotEmpty()) {
            val combinedFilters = prepFilters.joinToString(",")
            filterComplexParts.add("[0:v]${combinedFilters}[cfv]")
            currentInputVideoLabel = "[cfv]"
        }

        val (videoStages, finalVideoLabel) = buildVideoFilterStages(
            operations = videoOps,
            fontFilePath = fontFilePath,
            inputLabel = currentInputVideoLabel,
            imageInputIndices = imageInputIndices,
            density = density
        )
        filterComplexParts.addAll(videoStages)

        var finalAudioLabel: String? = null
        val mainVideoMuted = operations.filterIsInstance<EditOperation.MuteClip>().find { it.index == 0 }?.isMuted ?: false
        val effectiveAudioMuted = audioMuted || (mainVideoMuted && audioInputIndices.isEmpty())

        if (effectiveAudioMuted) {
            // Audio muted
        } else if (audioInputIndices.isNotEmpty()) {
            val mixInputLabels = mutableListOf<String>()

            for ((idx, pair) in audioInputIndices.withIndex()) {
                val (inputIdx, audioOp) = pair
                val trackLabel = "[a$idx]"
                val filters = mutableListOf<String>()

                val internalStartSec = audioOp.internalStartMs / 1000.0
                var internalEndSec = if (audioOp.internalEndMs > 0L) audioOp.internalEndMs / 1000.0 else Double.MAX_VALUE

                if (audioOp.startTimeMs != null && audioOp.endTimeMs != null) {
                    val timelineDurationSec = (audioOp.endTimeMs - audioOp.startTimeMs) / 1000.0
                    val maxEndSec = internalStartSec + timelineDurationSec
                    if (maxEndSec < internalEndSec) {
                        internalEndSec = maxEndSec
                    }
                }

                if (internalStartSec > 0.0 || internalEndSec != Double.MAX_VALUE) {
                    if (internalEndSec != Double.MAX_VALUE) {
                        filters.add("atrim=start=$internalStartSec:end=$internalEndSec,asetpts=PTS-STARTPTS")
                    } else {
                        filters.add("atrim=start=$internalStartSec,asetpts=PTS-STARTPTS")
                    }
                }
                if (audioOp.fadeInDurationMs > 0L) {
                    val fadeSec = audioOp.fadeInDurationMs / 1000.0
                    filters.add("afade=t=in:st=0:d=$fadeSec")
                }
                if (audioOp.fadeOutDurationMs > 0L) {
                    val fadeSec = audioOp.fadeOutDurationMs / 1000.0
                    val clipDur = if (audioOp.endTimeMs != null && audioOp.startTimeMs != null) {
                        (audioOp.endTimeMs - audioOp.startTimeMs) / 1000.0
                    } else if (audioOp.internalEndMs > 0L) {
                        (audioOp.internalEndMs - audioOp.internalStartMs) / 1000.0
                    } else {
                        (audioOp.originalDurationMs - audioOp.internalStartMs) / 1000.0
                    }
                    val fadeOutStart = maxOf(0.0, clipDur - fadeSec)
                    filters.add("afade=t=out:st=$fadeOutStart:d=$fadeSec")
                }
                var delayMs = audioOp.startTimeMs ?: 0L
                if (delayMs < 0) delayMs = 0L
                if (delayMs > 0) {
                    filters.add("adelay=$delayMs|$delayMs")
                }

                if (audioOp.volume != 1.0f) {
                    filters.add("volume=${audioOp.volume}")
                }

                if (filters.isNotEmpty()) {
                    filterComplexParts.add("[$inputIdx:a]${filters.joinToString(",")}$trackLabel")
                    mixInputLabels.add(trackLabel)
                } else {
                    mixInputLabels.add("[$inputIdx:a]")
                }
            }

            if (hasAudio && !mainVideoMuted && !audioInputIndices.any { it.second.removeOriginalAudio }) {
                var mainAudioRef = "[0:a]"
                val duckingCount = audioInputIndices.count { it.second.ducking }

                if (duckingCount > 0) {
                    val splits = (0..duckingCount).map { "[main_split_$it]" }
                    filterComplexParts.add("${mainAudioRef}asplit=${duckingCount + 1}${splits.joinToString("")}")
                    mainAudioRef = splits[0]

                    var splitIdx = 1
                    for (i in mixInputLabels.indices) {
                        val op = audioInputIndices[i].second
                        if (op.ducking) {
                            val bgLabel = mixInputLabels[i]
                            val sidechainLabel = splits[splitIdx++]
                            val duckedLabel = "[ducked_$i]"
                            filterComplexParts.add("${bgLabel}aformat=sample_rates=44100:channel_layouts=stereo[bg_fmt_$i]")
                            filterComplexParts.add("${sidechainLabel}aformat=sample_rates=44100:channel_layouts=stereo[sc_fmt_$i]")
                            filterComplexParts.add("[bg_fmt_$i][sc_fmt_$i]sidechaincompress=threshold=0.03:ratio=4:attack=5:release=500${duckedLabel}")
                            mixInputLabels[i] = duckedLabel
                        }
                    }
                }

                val allInputs = mainAudioRef + mixInputLabels.joinToString("")
                val totalInputs = 1 + mixInputLabels.size
                filterComplexParts.add("${allInputs}amix=inputs=$totalInputs:duration=longest[outa]")
                finalAudioLabel = "[outa]"
            } else {
                if (mixInputLabels.size == 1) {
                    val singleLabel = mixInputLabels[0]
                    filterComplexParts.add("${singleLabel}aformat=sample_rates=44100:channel_layouts=stereo[outa]")
                    finalAudioLabel = "[outa]"
                } else {
                    val allBg = mixInputLabels.joinToString("")
                    filterComplexParts.add("${allBg}amix=inputs=${mixInputLabels.size}:duration=longest[outa]")
                    finalAudioLabel = "[outa]"
                }
            }
        }

        val hasVideoFilters = videoStages.isNotEmpty() || prepFilters.isNotEmpty()
        val hasAudioFilters = finalAudioLabel != null

        if (hasVideoFilters || hasAudioFilters) {
            var mappedVideoLabel = finalVideoLabel
            if (hasVideoFilters) {
                val fmtLabel = "[fmtv]"
                filterComplexParts.add("${finalVideoLabel}scale=-2:${exportResolution},fps=${exportFps},format=yuv420p${fmtLabel}")
                mappedVideoLabel = fmtLabel
            }

            if (exportAudioOnly && hasVideoFilters) {
                filterComplexParts.add("${mappedVideoLabel}nullsink")
            }

            cmd.append(" -filter_complex \"${filterComplexParts.joinToString(";")}\"")

            if (!exportAudioOnly) {
                if (hasVideoFilters) {
                    cmd.append(" -map \"$mappedVideoLabel\"")
                } else {
                    cmd.append(" -map 0:v")
                }
            }

            if (effectiveAudioMuted) {
                cmd.append(" -an")
            } else if (hasAudioFilters) {
                cmd.append(" -map \"$finalAudioLabel\"")
            } else {
                cmd.append(" -map 0:a?")
            }
        } else {
            if (exportAudioOnly) {
                cmd.append(" -vn")
                if (!effectiveAudioMuted) {
                    cmd.append(" -map 0:a?")
                }
            }
            if (effectiveAudioMuted) {
                cmd.append(" -an")
            }
        }

        if (exportAudioOnly) {
            if (!effectiveAudioMuted) {
                cmd.append(" -c:a libmp3lame -b:a 192k")
            }
        } else {
            val bitrate = when (exportResolution) {
                2160 -> "30M"
                1440 -> "16M"
                1080 -> "8M"
                720 -> "5M"
                480 -> "2M"
                else -> "1M"
            }
            if (!hasVideoFilters) {
                cmd.append(" -c:v h264_mediacodec -b:v $bitrate -vf scale=-2:${exportResolution} -r ${exportFps}")
            } else {
                cmd.append(" -c:v h264_mediacodec -b:v $bitrate")
            }

            if (!effectiveAudioMuted) {
                cmd.append(" -c:a aac")
            }
        }

        if (outputDuration != null) {
            cmd.append(" -t $outputDuration")
        }
        cmd.append(" \"$outputFilePath\"")

        val finalCommand = cmd.toString()
        Log.d(TAG, "Built command: $finalCommand")
        return finalCommand
    }

    fun buildPreviewCommand(
        project: VideoProject,
        sourceFilePath: String,
        previewOutputPath: String,
        seekPositionMs: Long,
        fontFilePath: String? = null,
        density: Float = 1.0f
    ): String? {
        val operations = project.operations.filterNot { it is EditOperation.Merge }

        if (operations.none { it is EditOperation.Crop || it is EditOperation.AddText || it is EditOperation.AddSubtitles }) {
            return null
        }

        val videoOps = operations.filter { it is EditOperation.Crop || it is EditOperation.AddText || it is EditOperation.AddSubtitles }
        val trimOp = operations.filterIsInstance<EditOperation.Trim>().lastOrNull()

        val cmd = StringBuilder()
        var outputDuration: Double? = null
        if (trimOp != null) {
            val durationSecs = (trimOp.endMs - trimOp.startMs) / 1000.0
            outputDuration = durationSecs
            cmd.append("-ss ${trimOp.startMs / 1000.0} -t $durationSecs -i \"$sourceFilePath\"")
        } else {
            cmd.append("-i \"$sourceFilePath\"")
        }

        val (videoStages, finalLabel) = buildVideoFilterStages(
            operations = videoOps,
            fontFilePath = fontFilePath,
            density = density
        )
        if (videoStages.isNotEmpty()) {
            cmd.append(" -filter_complex \"${videoStages.joinToString(";")}\"")
            cmd.append(" -map \"$finalLabel\" -map 0:a?")
        }

        cmd.append(" -c:v h264_mediacodec -b:v 1500k -c:a aac")
        if (outputDuration != null) {
            cmd.append(" -t $outputDuration")
        }
        cmd.append(" -y \"$previewOutputPath\"")

        val finalCommand = cmd.toString()
        Log.d(TAG, "Built preview command: $finalCommand")
        return finalCommand
    }

    fun buildMergeCommand(
        context: Context,
        currentVideoPath: String,
        videoUrisToMerge: List<Uri>,
        listFilePath: String,
        outputFilePath: String
    ): String {
        val listContent = StringBuilder()
        listContent.append("file '$currentVideoPath'\n")

        for (uri in videoUrisToMerge) {
            val tempFilePath = copyContentUriToTempFile(context, uri)
            if (tempFilePath != null) {
                listContent.append("file '$tempFilePath'\n")
            } else {
                Log.e(TAG, "Skipping URI due to copy failure: $uri")
            }
        }

        File(listFilePath).writeText(listContent.toString())
        return "-f concat -safe 0 -i \"$listFilePath\" -c:v copy -c:a copy \"$outputFilePath\""
    }

    private fun buildVideoFilterStages(
        operations: List<EditOperation>,
        fontFilePath: String?,
        inputLabel: String = "[0:v]",
        imageInputIndices: List<Pair<Int, EditOperation.AddImageOverlay>> = emptyList(),
        density: Float = 1.0f
    ): Pair<List<String>, String> {
        val stages = mutableListOf<String>()
        var currentLabel = inputLabel
        var stageIndex = 0

        val overlayOps = operations.filterNot { it is EditOperation.Crop }
        val cropOps = operations.filterIsInstance<EditOperation.Crop>()

        for (op in overlayOps) {
            when (op) {
                is EditOperation.AddText -> {
                    val filterExpr = buildDrawtextExpr(op, fontFilePath)
                    val nextLabel = "[v$stageIndex]"
                    stages.add("$currentLabel$filterExpr$nextLabel")
                    currentLabel = nextLabel
                    stageIndex++
                }
                is EditOperation.AddImageOverlay -> {
                    val imageInputIndex = imageInputIndices.find { it.second.id == op.id }?.first
                    if (imageInputIndex != null) {
                        val radians = op.rotationAngle * Math.PI / 180.0
                        val scaledImgLabel = "[scaled_img_$stageIndex]"
                        val refVidLabel = "[ref_vid_$stageIndex]"
                        val rotatedImgLabel = "[rotated_img_$stageIndex]"
                        val nextLabel = "[v$stageIndex]"

                        val path = op.imageUri.path
                        val isGif = path != null && path.endsWith(".gif", ignoreCase = true)
                        val isVideo = path != null && (path.endsWith(".mp4", ignoreCase = true) ||
                                                       path.endsWith(".mkv", ignoreCase = true) ||
                                                       path.endsWith(".mov", ignoreCase = true) ||
                                                       path.endsWith(".3gp", ignoreCase = true))

                        if (isVideo) {
                            val startSec = (op.startTimeMs ?: 0L) / 1000.0
                            val ptsLabel = "[pts_$stageIndex]"
                            val mirrorStr = if (op.isMirrored) ",hflip" else ""
                            val speedExpr = if (!op.speedKeyframes.isNullOrEmpty()) {
                                buildFFmpegInterpolationExpr(op.speedKeyframes, useValueY = false, defaultValue = 1.0f, startTimeMs = 0L, timeVar = "T")
                            } else {
                                "1.0"
                            }
                            val safeSpeedExpr = "if(gt($speedExpr,0.1),$speedExpr,0.1)"
                            stages.add("[$imageInputIndex:v]setpts='(PTS-STARTPTS)/($safeSpeedExpr)+${startSec}/TB',format=rgba$mirrorStr$ptsLabel")
                            stages.add("${ptsLabel}${currentLabel}scale2ref=w=iw*${op.relativeWidth}:h=ih*${op.relativeHeight}${scaledImgLabel}${refVidLabel}")
                        } else {
                            val rgbaImgLabel = "[rgba_img_$stageIndex]"
                            val mirrorStr = if (op.isMirrored) ",hflip" else ""
                            if (!op.opacityKeyframes.isNullOrEmpty()) {
                                stages.add("[$imageInputIndex:v]format=rgba$mirrorStr,loop=loop=-1:size=1:start=0,fps=25$rgbaImgLabel")
                            } else {
                                stages.add("[$imageInputIndex:v]format=rgba$mirrorStr$rgbaImgLabel")
                            }
                            stages.add("${rgbaImgLabel}${currentLabel}scale2ref=w=iw*${op.relativeWidth}:h=ih*${op.relativeHeight}${scaledImgLabel}${refVidLabel}")
                        }

                        var currentOverlayLabel = scaledImgLabel
                        if (op.chromaKeyColor != null) {
                            val colorkeyLabel = "[colorkey_$stageIndex]"
                            val color = formatColorForFFmpeg(op.chromaKeyColor)
                            stages.add("${currentOverlayLabel}colorkey=${color}:${op.chromaKeySimilarity}:0.1${colorkeyLabel}")
                            currentOverlayLabel = colorkeyLabel
                        }

                        if (!op.opacityKeyframes.isNullOrEmpty()) {
                            val opacityLabel = "[opacity_$stageIndex]"
                            val alphaExpr = buildFFmpegInterpolationExpr(op.opacityKeyframes, useValueY = false, defaultValue = op.opacity, startTimeMs = 0L, timeVar = "T")
                            stages.add("${currentOverlayLabel}format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*($alphaExpr)'${opacityLabel}")
                            currentOverlayLabel = opacityLabel
                        } else if (op.opacity < 1.0f) {
                            val opacityLabel = "[opacity_$stageIndex]"
                            stages.add("${currentOverlayLabel}format=rgba,colorchannelmixer=aa=${op.opacity}${opacityLabel}")
                            currentOverlayLabel = opacityLabel
                        }

                        if (op.maskConfig.shape != EditOperation.MaskShape.NONE) {
                            val maskLabel = "[mask_$stageIndex]"
                            val mc = op.maskConfig
                            val cx = "W*${mc.relativeX}"
                            val cy = "H*${mc.relativeY}"
                            val mw = "W*${mc.relativeWidth}"
                            val mh = "H*${mc.relativeHeight}"
                            val rad = Math.toRadians(mc.rotationAngle.toDouble())
                            val cosA = Math.cos(rad)
                            val sinA = Math.sin(rad)

                            val dx = "(X - $cx)"
                            val dy = "(Y - $cy)"
                            val rx = "($dx * $cosA - $dy * $sinA)"
                            val ry = "($dx * $sinA + $dy * $cosA)"

                            val shapeExpr = when (mc.shape) {
                                EditOperation.MaskShape.RECTANGLE -> "if(lt(abs($rx), $mw/2) * lt(abs($ry), $mh/2), 255, 0)"
                                EditOperation.MaskShape.ELLIPSE -> "if(lte(pow($rx/($mw/2), 2) + pow($ry/($mh/2), 2), 1), 255, 0)"
                                EditOperation.MaskShape.SPLIT -> "if(gt($ry, 0), 255, 0)"
                                EditOperation.MaskShape.SHUTTER -> "if(lt(abs($ry), $mh/2), 255, 0)"
                                else -> "255"
                            }

                            val finalAlphaExpr = if (mc.isInverted) "(255 - ($shapeExpr))" else "($shapeExpr)"
                            stages.add("${currentOverlayLabel}format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*($finalAlphaExpr/255)'${maskLabel}")
                            currentOverlayLabel = maskLabel
                        }

                        stages.add("${currentOverlayLabel}rotate=$radians:c=none:ow='rotw($radians)':oh='roth($radians)'${rotatedImgLabel}")
                        val enablePart = buildEnableExpr(op.startTimeMs, op.endTimeMs)
                        val shortestPart = if (((isGif || isVideo) && op.isLooping) || (!isGif && !isVideo && !op.opacityKeyframes.isNullOrEmpty())) ":shortest=1" else ""

                        val overlayX = if (!op.positionKeyframes.isNullOrEmpty()) {
                            val xExpr = buildFFmpegInterpolationExpr(op.positionKeyframes, useValueY = false, defaultValue = op.relativeX, startTimeMs = op.startTimeMs ?: 0L)
                            "x='(W*($xExpr))-(w/2)'"
                        } else {
                            "x='(W*${op.relativeX})-(w/2)'"
                        }

                        val overlayY = if (!op.positionKeyframes.isNullOrEmpty()) {
                            val yExpr = buildFFmpegInterpolationExpr(op.positionKeyframes, useValueY = true, defaultValue = op.relativeY, startTimeMs = op.startTimeMs ?: 0L)
                            "y='(H*($yExpr))-(h/2)'"
                        } else {
                            "y='(H*${op.relativeY})-(h/2)'"
                        }

                        stages.add("${refVidLabel}${rotatedImgLabel}overlay=$overlayX:$overlayY${shortestPart}${enablePart}${nextLabel}")
                        currentLabel = nextLabel
                        stageIndex++
                    }
                }
                is EditOperation.AddSubtitles -> {
                    for (cue in op.cues) {
                        val escapedText = cue.text
                            .replace("\\", "\\\\")
                            .replace("'", "\\\\'")
                            .replace(":", "\\:")
                            .replace("\n", "\n")

                        val fontPart = if (!fontFilePath.isNullOrBlank()) {
                            val escapedFont = fontFilePath
                                .replace("\\", "\\\\")
                                .replace("'", "\\'")
                                .replace(":", "\\:")
                            "fontfile='$escapedFont':"
                        } else {
                            ""
                        }

                        val startSec = cue.startTimeMs / 1000.0
                        val endSec = cue.endTimeMs / 1000.0
                        val enablePart = ":enable='between(t,$startSec,$endSec)'"

                        val posPart = if (op.hasCustomPosition()) {
                            "x='(w*${op.relativeX})-(tw/2)':y='(h*${op.relativeY})-(th/2)'"
                        } else {
                            when (op.position) {
                                TextPosition.TOP_LEFT -> "x=24:y=24"
                                TextPosition.TOP_CENTER, TextPosition.CENTER_TOP -> "x=(w-tw)/2:y=24"
                                TextPosition.TOP_RIGHT -> "x=w-tw-24:y=24"
                                TextPosition.CENTER_LEFT -> "x=24:y=(h-th)/2"
                                TextPosition.CENTER -> "x=(w-tw)/2:y=(h-th)/2"
                                TextPosition.CENTER_RIGHT -> "x=w-tw-24:y=(h-th)/2"
                                TextPosition.BOTTOM_LEFT -> "x=24:y=h-th-24"
                                TextPosition.BOTTOM_CENTER, TextPosition.CENTER_BOTTOM -> "x=(w-tw)/2:y=h-th-24"
                                TextPosition.BOTTOM_RIGHT -> "x=w-tw-24:y=h-th-24"
                            }
                        }

                        val boxPart = ":box=1:boxcolor='0x00000080':boxborderw=8"
                        val filterExpr = "drawtext=${fontPart}text='$escapedText':fontcolor='white':fontsize=${op.fontSize}:${posPart}${boxPart}$enablePart"

                        val nextLabel = "[v$stageIndex]"
                        stages.add("$currentLabel$filterExpr$nextLabel")
                        currentLabel = nextLabel
                        stageIndex++
                    }
                }
                else -> {}
            }
        }

        for (op in cropOps) {
            val filterExpr = buildCropFilterExpr(op)
            if (filterExpr != null) {
                val nextLabel = "[v$stageIndex]"
                stages.add("$currentLabel$filterExpr$nextLabel")
                currentLabel = nextLabel
                stageIndex++
            }
        }

        return Pair(stages, currentLabel)
    }

    private fun buildCropFilterExpr(op: EditOperation.Crop): String? = when (op.aspectRatio) {
        "16:9" -> "crop='trunc(min(iw,ih*16/9)/2)*2':'trunc(min(ih,iw*9/16)/2)*2',setsar=1"
        "9:16" -> "crop='trunc(min(iw,ih*9/16)/2)*2':'trunc(min(ih,iw*16/9)/2)*2',setsar=1"
        "1:1"  -> "crop='trunc(min(iw,ih)/2)*2':'trunc(min(iw,ih)/2)*2',setsar=1"
        "Custom" -> {
            val w = String.format(java.util.Locale.US, "trunc(iw*%.4f/2)*2", op.wFraction)
            val h = String.format(java.util.Locale.US, "trunc(ih*%.4f/2)*2", op.hFraction)
            val x = String.format(java.util.Locale.US, "trunc(iw*%.4f/2)*2", op.xFraction)
            val y = String.format(java.util.Locale.US, "trunc(ih*%.4f/2)*2", op.yFraction)
            "crop=w=$w:h=$h:x='min($x,iw-($w))':y='min($y,ih-($h))',setsar=1"
        }
        else   -> null
    }

    private fun buildDrawtextExpr(op: EditOperation.AddText, fontFilePath: String?): String {
        val escapedText = op.text
            .replace("\\", "\\\\")
            .replace("'", "\\\\'")
            .replace(":", "\\:")

        val fontToUse = op.fontPath ?: fontFilePath
        val fontPart = if (!fontToUse.isNullOrBlank() && File(fontToUse).exists()) {
            val escapedFont = fontToUse
                .replace("\\", "\\\\")
                .replace("'", "\\'")
                .replace(":", "\\:")
            "fontfile='$escapedFont':"
        } else {
            Log.w(TAG, "Font path null or missing on disk ($fontToUse) — omitting fontfile param for FFmpeg default font.")
            ""
        }

        val positionPart = if (!op.positionKeyframes.isNullOrEmpty()) {
            val xExpr = buildFFmpegInterpolationExpr(op.positionKeyframes, useValueY = false, defaultValue = op.relativeX ?: 0.5f, startTimeMs = op.startTimeMs ?: 0L)
            val yExpr = buildFFmpegInterpolationExpr(op.positionKeyframes, useValueY = true, defaultValue = op.relativeY ?: 0.5f, startTimeMs = op.startTimeMs ?: 0L)
            "x='(w*($xExpr))-(tw/2)':y='(h*($yExpr))-(th/2)'"
        } else if (op.hasCustomPosition()) {
            "x='(w*${op.relativeX})-(tw/2)':y='(h*${op.relativeY})-(th/2)'"
        } else {
            op.position.ffmpegParam
        }

        val enablePart = buildEnableExpr(op.startTimeMs, op.endTimeMs)

        val alphaPart = if (!op.opacityKeyframes.isNullOrEmpty()) {
            val alphaExpr = buildFFmpegInterpolationExpr(op.opacityKeyframes, useValueY = false, defaultValue = op.opacity, startTimeMs = op.startTimeMs ?: 0L)
            ":alpha='$alphaExpr'"
        } else if (op.opacity < 1.0f) {
            ":alpha='${op.opacity}'"
        } else {
            ""
        }
        val borderPart = if (op.borderThickness > 0) ":borderw=${op.borderThickness}:bordercolor='${formatColorForFFmpeg(op.borderColor)}'" else ""
        val alignPart = if (!op.textAlign.isNullOrBlank()) ":text_align=${op.textAlign}" else ""
        val lineSpacingPart = if (op.lineSpacing != 0f) ":line_spacing=${op.lineSpacing.toInt()}" else ""

        return "drawtext=${fontPart}text='$escapedText':fontcolor='${formatColorForFFmpeg(op.color)}':fontsize=${op.fontSize}:$positionPart$enablePart$alphaPart$borderPart$alignPart$lineSpacingPart"
    }

    private fun buildFFmpegInterpolationExpr(
        keyframes: List<EditOperation.KeyframePoint>?,
        useValueY: Boolean,
        defaultValue: Float,
        startTimeMs: Long,
        timeVar: String = "t"
    ): String {
        if (keyframes.isNullOrEmpty()) return defaultValue.toString()
        val sorted = keyframes.sortedBy { it.timeMs }
        val startSec = startTimeMs / 1000.0
        val tRel = "($timeVar-$startSec)"

        if (sorted.size == 1) {
            val v = if (useValueY) sorted[0].valueY else sorted[0].valueX
            return v.toString()
        }

        var expr = ""
        val lastVal = if (useValueY) sorted.last().valueY else sorted.last().valueX
        expr = lastVal.toString()

        for (i in sorted.size - 2 downTo 0) {
            val k1 = sorted[i]
            val k2 = sorted[i + 1]
            val t1 = k1.timeMs / 1000.0
            val t2 = k2.timeMs / 1000.0
            val v1 = if (useValueY) k1.valueY else k1.valueX
            val v2 = if (useValueY) k2.valueY else k2.valueX

            val diffVal = v2 - v1
            val diffTime = t2 - t1
            val segmentExpr = if (diffTime > 0) {
                "$v1 + ($diffVal) * ($tRel - $t1) / ($diffTime)"
            } else {
                v1.toString()
            }

            expr = "if(lt($tRel, $t2), $segmentExpr, $expr)"
        }

        val firstVal = if (useValueY) sorted.first().valueY else sorted.first().valueX
        val firstTime = sorted.first().timeMs / 1000.0
        expr = "if(lt($tRel, $firstTime), $firstVal, $expr)"

        return expr
    }

    private fun formatColorForFFmpeg(colorHex: String): String {
        if (!colorHex.startsWith("#")) return colorHex
        return when (colorHex.length) {
            9 -> {
                val aa = colorHex.substring(1, 3)
                val rrggbb = colorHex.substring(3)
                "0x$rrggbb$aa"
            }
            7 -> {
                "0x${colorHex.substring(1)}"
            }
            else -> colorHex
        }
    }

    private fun buildEnableExpr(startTimeMs: Long?, endTimeMs: Long?): String {
        if (startTimeMs == null && endTimeMs == null) return ""
        val startSec = maxOf(0L, startTimeMs ?: 0L) / 1000.0
        return if (endTimeMs != null) {
            val endSec = maxOf(0L, endTimeMs) / 1000.0
            ":enable='between(t,$startSec,$endSec)'"
        } else {
            ":enable='gte(t,$startSec)'"
        }
    }

    private fun getFFmpegFilterForAdjust(op: EditOperation.Adjust): String? {
        val filters = mutableListOf<String>()

        if (op.brightness != 0 || op.contrast != 0 || op.saturation != 0) {
            val b = op.brightness / 100.0
            val c = 1.0 + (op.contrast / 100.0)
            val s = 1.0 + (op.saturation / 100.0)
            filters.add("eq=brightness=$b:contrast=$c:saturation=$s")
        }

        if (op.exposure != 0) {
            val ev = (op.exposure / 100.0) * 3.0
            filters.add("exposure=exposure=$ev")
        }

        if (op.warmth != 0) {
            val w = (op.warmth / 100.0) * 0.3
            filters.add("colorbalance=rs=$w:rm=$w:rh=$w:bs=${-w}:bm=${-w}:bh=${-w}")
        }

        if (op.shadow != 0 || op.highlights != 0) {
            Log.w(TAG, "Shadow and highlight adjustments are skipped on native FFmpeg.")
        }

        if (op.sharpen != 0) {
            val amt = (op.sharpen / 100.0) * 1.5
            filters.add("unsharp=luma_amount=$amt")
        }

        if (op.vignette != 0) {
            val angle = 1.5 - (op.vignette / 100.0) * 0.9
            filters.add("vignette=angle=$angle")
        }

        return if (filters.isNotEmpty()) filters.joinToString(",") else null
    }

    private fun getFFmpegFilterForName(name: String): String? {
        return when (name.lowercase()) {
            "vintage" -> "curves=preset=vintage"
            "warm" -> "colorchannelmixer=1.1:0:0:0:0:1.0:0:0:0:0:0.9"
            "cool" -> "colorchannelmixer=0.9:0:0:0:0:1.0:0:0:0:0:1.1"
            "contrast" -> "curves=preset=strong_contrast"
            "monochrome" -> "hue=s=0"
            "vignette" -> "vignette"
            "negative" -> "curves=preset=negative"
            "crossprocess" -> "curves=preset=cross_process"
            else -> null
        }
    }

    private fun copyContentUriToTempFile(context: Context, uri: Uri): String? {
        return try {
            val tempFile = File.createTempFile("temp_video", ".mp4", context.cacheDir)
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { input.copyTo(it) }
            }
            tempFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy content URI: ${e.message}")
            null
        }
    }
}
