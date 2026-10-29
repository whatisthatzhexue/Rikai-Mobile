/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: a compact MangaOCR pipeline for offline manga and
 * vertical Japanese pages. DBNet boxes are clustered into speech-bubble-like
 * regions, each region is cropped, and the manga-ocr ViT encoder + greedy
 * decoder produce one text block per region. Overlay translation, speculative
 * decoding, mask refinement and mixed-script correction are intentionally left
 * out of this app.
 */
package com.rikai.ocr

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import android.os.SystemClock
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.roundToInt

internal data class MangaRect(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
    val centerX: Float get() = (left + right) / 2f
    val centerY: Float get() = (top + bottom) / 2f
    val area: Int get() = width.coerceAtLeast(0) * height.coerceAtLeast(0)
}

internal data class MangaBubble(
    /** Cropped rectangle, including the small padding around the text. */
    val rect: MangaRect,
    /** Confirmed text extent used for the returned block bounds. */
    val contentRect: MangaRect,
    val memberIndices: List<Int>,
)

internal data class MangaCropPlan(
    val sourceBubbleIndex: Int,
    val cropIndex: Int,
    val cropCount: Int,
    val bubble: MangaBubble,
)

/**
 * Groups DBNet line boxes into manga speech-bubble-sized regions using
 * edge-distance union-find. A whole bubble is recognized at once because
 * manga-ocr was trained on multi-column bubble crops, not individual lines.
 */
internal object MangaBubbleClusterer {
    fun cluster(
        rects: List<MangaRect>,
        imageWidth: Int,
        imageHeight: Int,
        padding: Int = 6,
        gap: Int = 18,
    ): List<MangaBubble> {
        if (rects.isEmpty()) return emptyList()
        val parent = IntArray(rects.size) { it }

        fun find(value: Int): Int {
            var current = value
            while (parent[current] != current) {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }

        fun union(first: Int, second: Int) {
            val a = find(first)
            val b = find(second)
            if (a != b) parent[a] = b
        }

        val maximumGap = gap.coerceAtLeast(0)
        for (i in rects.indices) {
            for (j in i + 1 until rects.size) {
                if (withinGap(rects[i], rects[j], maximumGap) &&
                    !perpendicularScaleBridge(rects[i], rects[j])
                ) {
                    union(i, j)
                }
            }
        }

        val groups = LinkedHashMap<Int, MutableList<Int>>()
        for (index in rects.indices) {
            groups.getOrPut(find(index)) { mutableListOf() }.add(index)
        }
        val safePadding = padding.coerceAtLeast(0)
        return groups.values.map { members ->
            var left = Int.MAX_VALUE
            var top = Int.MAX_VALUE
            var right = Int.MIN_VALUE
            var bottom = Int.MIN_VALUE
            for (index in members) {
                val rect = rects[index]
                left = minOf(left, rect.left)
                top = minOf(top, rect.top)
                right = maxOf(right, rect.right)
                bottom = maxOf(bottom, rect.bottom)
            }
            val content = MangaRect(
                left = left.coerceIn(0, imageWidth),
                top = top.coerceIn(0, imageHeight),
                right = right.coerceIn(0, imageWidth),
                bottom = bottom.coerceIn(0, imageHeight),
            )
            MangaBubble(
                rect = MangaRect(
                    left = (left - safePadding).coerceAtLeast(0),
                    top = (top - safePadding).coerceAtLeast(0),
                    right = (right + safePadding).coerceAtMost(imageWidth),
                    bottom = (bottom + safePadding).coerceAtMost(imageHeight),
                ),
                contentRect = content,
                memberIndices = members.toList(),
            )
        }.sortedWith(compareBy({ it.rect.top }, { it.rect.left }))
    }

    private fun withinGap(first: MangaRect, second: MangaRect, gap: Int): Boolean {
        return axisGap(first.left, first.right, second.left, second.right) <= gap &&
            axisGap(first.top, first.bottom, second.top, second.bottom) <= gap
    }

    private fun axisGap(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int): Int = when {
        aEnd < bStart -> bStart - aEnd
        bEnd < aStart -> aStart - bEnd
        else -> 0
    }

    private fun perpendicularScaleBridge(first: MangaRect, second: MangaRect): Boolean {
        return wideBridge(first, second) ||
            wideBridge(second, first) ||
            tallBridge(first, second) ||
            tallBridge(second, first)
    }

    private fun wideBridge(candidate: MangaRect, line: MangaRect): Boolean =
        line.height >= line.width * 2 &&
            candidate.height < candidate.width * 2 &&
            candidate.width * 2 >= line.width * 5

    private fun tallBridge(candidate: MangaRect, line: MangaRect): Boolean =
        line.width >= line.height * 2 &&
            candidate.width < candidate.height * 2 &&
            candidate.height * 2 >= line.height * 5
}

/**
 * Splits a dense bubble into at most [MAX_TEXT_BANDS_PER_CROP] column/row bands
 * so the fixed 224px encoder does not squash a whole page into unreadable
 * glyphs.
 */
internal object MangaCropPlanner {
    const val MAX_TEXT_BANDS_PER_CROP: Int = 6

    fun plan(
        bubbles: List<MangaBubble>,
        rects: List<MangaRect>,
        imageWidth: Int,
        imageHeight: Int,
        padding: Int,
    ): List<MangaCropPlan> = bubbles.flatMapIndexed { bubbleIndex, bubble ->
        val members = bubble.memberIndices.mapNotNull { index ->
            rects.getOrNull(index)?.let { IndexedRect(index, it) }
        }
        if (members.isEmpty()) {
            return@flatMapIndexed listOf(
                MangaCropPlan(bubbleIndex, cropIndex = 0, cropCount = 1, bubble = bubble),
            )
        }
        val vertical = inferVertical(
            sourceBoxes = members.map { it.rect },
            blockBounds = bubble.contentRect,
        )
        val bands = groupIntoBands(members, vertical)
        if (bands.size <= MAX_TEXT_BANDS_PER_CROP) {
            return@flatMapIndexed listOf(
                MangaCropPlan(bubbleIndex, cropIndex = 0, cropCount = 1, bubble = bubble),
            )
        }
        val chunks = bands.chunked(MAX_TEXT_BANDS_PER_CROP)
        chunks.mapIndexed { cropIndex, chunk ->
            MangaCropPlan(
                sourceBubbleIndex = bubbleIndex,
                cropIndex = cropIndex,
                cropCount = chunks.size,
                bubble = bubbleForMembers(
                    members = chunk.flatten(),
                    imageWidth = imageWidth,
                    imageHeight = imageHeight,
                    padding = padding,
                ),
            )
        }
    }

    private fun inferVertical(sourceBoxes: List<MangaRect>, blockBounds: MangaRect): Boolean {
        var portrait = 0
        var landscape = 0
        for (box in sourceBoxes) {
            val width = box.width.coerceAtLeast(1)
            val height = box.height.coerceAtLeast(1)
            when {
                height >= width * 1.2f -> portrait++
                width >= height * 1.2f -> landscape++
            }
        }
        return when {
            portrait > landscape -> true
            landscape > portrait -> false
            blockBounds.height >= blockBounds.width * 1.3f -> true
            else -> false
        }
    }

    private fun groupIntoBands(
        members: List<IndexedRect>,
        vertical: Boolean,
    ): List<List<IndexedRect>> {
        val sorted = if (vertical) {
            members.sortedWith(
                compareByDescending<IndexedRect> { it.rect.centerX }
                    .thenBy { it.rect.top },
            )
        } else {
            members.sortedWith(
                compareBy<IndexedRect> { it.rect.centerY }
                    .thenBy { it.rect.left },
            )
        }
        val bands = mutableListOf<MutableList<IndexedRect>>()
        for (member in sorted) {
            val current = bands.lastOrNull()
            if (current != null && sameBand(member, current, vertical)) {
                current += member
            } else {
                bands += mutableListOf(member)
            }
        }
        return bands
    }

    private fun sameBand(
        candidate: IndexedRect,
        band: List<IndexedRect>,
        vertical: Boolean,
    ): Boolean {
        val candidateCenter = if (vertical) candidate.rect.centerX else candidate.rect.centerY
        val bandCenter = band.map {
            if (vertical) it.rect.centerX else it.rect.centerY
        }.average().toFloat()
        val candidateThickness = if (vertical) candidate.rect.width else candidate.rect.height
        val bandThickness = band.maxOf {
            if (vertical) it.rect.width else it.rect.height
        }
        return abs(candidateCenter - bandCenter) <=
            maxOf(candidateThickness, bandThickness) * 0.5f
    }

    private fun bubbleForMembers(
        members: List<IndexedRect>,
        imageWidth: Int,
        imageHeight: Int,
        padding: Int,
    ): MangaBubble {
        val left = members.minOf { it.rect.left }
        val top = members.minOf { it.rect.top }
        val right = members.maxOf { it.rect.right }
        val bottom = members.maxOf { it.rect.bottom }
        val content = MangaRect(
            left = left.coerceIn(0, imageWidth),
            top = top.coerceIn(0, imageHeight),
            right = right.coerceIn(0, imageWidth),
            bottom = bottom.coerceIn(0, imageHeight),
        )
        val safePadding = padding.coerceAtLeast(0)
        return MangaBubble(
            rect = MangaRect(
                left = (left - safePadding).coerceAtLeast(0),
                top = (top - safePadding).coerceAtLeast(0),
                right = (right + safePadding).coerceAtMost(imageWidth),
                bottom = (bottom + safePadding).coerceAtMost(imageHeight),
            ),
            contentRect = content,
            memberIndices = members.map { it.index },
        )
    }

    private data class IndexedRect(val index: Int, val rect: MangaRect)
}

internal class MangaOcrRecognizer {
    private var encoderSession: OrtSession? = null
    private var decoderSession: OrtSession? = null
    private var tokens: Array<String> = emptyArray()
    private var encoderInputName: String = "pixel_values"
    private var encoderOutputName: String = "last_hidden_state"
    private var decoderInputIdsName: String = "input_ids"
    private var decoderHiddenName: String = "encoder_hidden_states"
    private var loadedEncoderPath: String? = null
    private var loadedDecoderPath: String? = null
    private var loadedVocabPath: String? = null

    @Synchronized
    fun initialize(
        encoderPath: String?,
        decoderPath: String?,
        vocabPath: String?,
    ): Map<String, Any>? {
        if (encoderPath.isNullOrBlank() || decoderPath.isNullOrBlank() || vocabPath.isNullOrBlank()) {
            close()
            return null
        }
        val encoderFile = File(encoderPath)
        val decoderFile = File(decoderPath)
        val vocabFile = File(vocabPath)
        for (file in listOf(encoderFile, decoderFile, vocabFile)) {
            if (!file.isFile || file.length() == 0L) {
                close()
                return null
            }
        }
        val absoluteEncoder = encoderFile.absolutePath
        val absoluteDecoder = decoderFile.absolutePath
        val absoluteVocab = vocabFile.absolutePath
        if (encoderSession != null &&
            decoderSession != null &&
            tokens.isNotEmpty() &&
            loadedEncoderPath == absoluteEncoder &&
            loadedDecoderPath == absoluteDecoder &&
            loadedVocabPath == absoluteVocab
        ) {
            return readiness(reused = true)
        }

        val parsed = runCatching {
            vocabFile.readLines(Charsets.UTF_8)
        }.getOrElse {
            close()
            return null
        }
        if (parsed.size < 100 ||
            parsed.getOrNull(PAD_ID) != "[PAD]" ||
            parsed.getOrNull(CLS_ID) != "[CLS]" ||
            parsed.getOrNull(SEP_ID) != "[SEP]"
        ) {
            close()
            return null
        }

        close()
        return try {
            val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
            val encoderOptions = OrtSession.SessionOptions()
            val decoderOptions = OrtSession.SessionOptions()
            var encoder: OrtSession? = null
            var decoder: OrtSession? = null
            try {
                encoderOptions.setIntraOpNumThreads(threads)
                encoderOptions.setInterOpNumThreads(1)
                decoderOptions.setIntraOpNumThreads(threads)
                decoderOptions.setInterOpNumThreads(1)
                encoder = OcrRuntime.environment.createSession(absoluteEncoder, encoderOptions)
                decoder = OcrRuntime.environment.createSession(absoluteDecoder, decoderOptions)
                encoderSession = encoder
                decoderSession = decoder
                tokens = parsed.toTypedArray()
                encoderInputName = encoder.inputNames.firstOrNull() ?: "pixel_values"
                encoderOutputName = pickName(
                    encoder.outputNames,
                    "last_hidden_state",
                    "hidden_states",
                    "output_0",
                )
                decoderInputIdsName = pickName(
                    decoder.inputNames,
                    "input_ids",
                    "decoder_input_ids",
                )
                decoderHiddenName = pickName(
                    decoder.inputNames,
                    "encoder_hidden_states",
                    "encoder_outputs",
                    "last_hidden_state",
                )
                loadedEncoderPath = absoluteEncoder
                loadedDecoderPath = absoluteDecoder
                loadedVocabPath = absoluteVocab
                readiness(reused = false)
            } catch (error: Throwable) {
                runCatching { decoder?.close() }
                runCatching { encoder?.close() }
                encoderSession = null
                decoderSession = null
                throw error
            } finally {
                encoderOptions.close()
                decoderOptions.close()
            }
        } catch (error: OutOfMemoryError) {
            close()
            throw OcrFailure("OOM", "加载 MangaOCR 模型时内存不足")
        } catch (error: Throwable) {
            close()
            throw OcrFailure("MODEL_INVALID", "无法加载 MangaOCR 模型：${error.message}")
        }
    }

    @Synchronized
    fun isReady(): Boolean =
        encoderSession != null && decoderSession != null && tokens.isNotEmpty()

    @Synchronized
    fun readiness(reused: Boolean = false): Map<String, Any> = mapOf(
        "encoderInput" to encoderInputName,
        "encoderOutput" to encoderOutputName,
        "decoderInputIds" to decoderInputIdsName,
        "decoderHidden" to decoderHiddenName,
        "vocab" to tokens.size,
        "reused" to reused,
    )

    @Synchronized
    fun recognize(
        bitmap: Bitmap,
        quads: List<DBPostprocessor.Quad>,
        onProgress: (stage: String, current: Int, total: Int) -> Unit,
        isCancelled: () -> Boolean,
    ): List<NativeOcrBlock> {
        val encoder = encoderSession ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 模型尚未初始化")
        val decoder = decoderSession ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 模型尚未初始化")
        if (tokens.isEmpty()) throw OcrFailure("ENGINE_ERROR", "MangaOCR 词表尚未加载")
        if (quads.isEmpty()) return emptyList()
        if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")

        val rects = quads.map { quad ->
            val bounds = quad.axisAlignedBounds()
            MangaRect(
                left = bounds[0].coerceIn(0, bitmap.width),
                top = bounds[1].coerceIn(0, bitmap.height),
                right = bounds[2].coerceIn(0, bitmap.width),
                bottom = bounds[3].coerceIn(0, bitmap.height),
            )
        }.filter { it.width > 1 && it.height > 1 }
        if (rects.isEmpty()) return emptyList()

        // Scale the clustering gap with the detected text size. A fixed 18 px
        // merges small furigana with neighbouring columns on dense pages and
        // over-separates large display lettering.
        val medianSide = rects.map { minOf(it.width, it.height).toFloat() }
            .sorted()
            .let { values ->
                if (values.size % 2 == 1) {
                    values[values.size / 2]
                } else {
                    (values[values.size / 2 - 1] + values[values.size / 2]) / 2f
                }
            }
        val gap = (medianSide * 0.4f).roundToInt().coerceIn(MIN_BUBBLE_GAP, MAX_BUBBLE_GAP)
        val padding = (medianSide * 0.15f).roundToInt()
            .coerceIn(MIN_CROP_PADDING, MAX_CROP_PADDING)
        val bubbles = MangaBubbleClusterer.cluster(
            rects = rects,
            imageWidth = bitmap.width,
            imageHeight = bitmap.height,
            padding = padding,
            gap = gap,
        )
        if (bubbles.isEmpty()) return emptyList()
        val plans = MangaCropPlanner.plan(
            bubbles = bubbles,
            rects = rects,
            imageWidth = bitmap.width,
            imageHeight = bitmap.height,
            padding = padding,
        )
        if (plans.isEmpty()) return emptyList()

        val chunks = mutableMapOf<Int, MutableList<RecognizedChunk>>()
        plans.forEachIndexed { planIndex, plan ->
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            val crop = crop(bitmap, plan.bubble.rect)
            if (crop != null) {
                try {
                    val recognized = recognizeCrop(crop, encoder, decoder, isCancelled)
                    if (recognized.text.isNotBlank()) {
                        chunks.getOrPut(plan.sourceBubbleIndex) { mutableListOf() }
                            .add(RecognizedChunk(plan.cropIndex, recognized))
                    }
                } finally {
                    if (!crop.isRecycled) crop.recycle()
                }
            }
            onProgress("recognize", planIndex + 1, plans.size)
        }

        val blocks = chunks.mapNotNull { (bubbleIndex, parts) ->
            val bubble = bubbles.getOrNull(bubbleIndex) ?: return@mapNotNull null
            val text = sanitizeText(
                parts.sortedBy { it.cropIndex }
                    .joinToString(separator = "") { it.result.text },
            )
            if (text.isEmpty() || !hasReadableCharacter(text)) return@mapNotNull null
            val confidence = parts.map { it.result.confidence }
                .filter { it.isFinite() }
                .average()
                .takeIf { it.isFinite() }
                ?.toFloat() ?: 0f
            // Drop decoder noise from low-quality crops. Correct manga-ocr
            // bubbles are normally well above this; the threshold is
            // deliberately conservative so short sound effects survive.
            if (confidence < MIN_BUBBLE_CONFIDENCE) return@mapNotNull null
            NativeOcrBlock(
                text = text,
                left = bubble.contentRect.left,
                top = bubble.contentRect.top,
                right = bubble.contentRect.right,
                bottom = bubble.contentRect.bottom,
                confidence = confidence.coerceIn(0f, 1f),
                orientation = "vertical",
                points = listOf(
                    bubble.contentRect.left.toDouble(),
                    bubble.contentRect.top.toDouble(),
                    bubble.contentRect.right.toDouble(),
                    bubble.contentRect.top.toDouble(),
                    bubble.contentRect.right.toDouble(),
                    bubble.contentRect.bottom.toDouble(),
                    bubble.contentRect.left.toDouble(),
                    bubble.contentRect.bottom.toDouble(),
                ),
            )
        }
        return sortVerticalBlocks(blocks)
    }

    @Synchronized
    fun close() {
        runCatching { encoderSession?.close() }
        runCatching { decoderSession?.close() }
        encoderSession = null
        decoderSession = null
        tokens = emptyArray()
        loadedEncoderPath = null
        loadedDecoderPath = null
        loadedVocabPath = null
    }

    private fun recognizeCrop(
        crop: Bitmap,
        encoder: OrtSession,
        decoder: OrtSession,
        isCancelled: () -> Boolean,
    ): RecognizedText {
        val input = preprocess224(crop)
        val inputTensor = OnnxTensor.createTensor(
            OcrRuntime.environment,
            directFloatBuffer(input),
            longArrayOf(1, 3, IMAGE_SIZE.toLong(), IMAGE_SIZE.toLong()),
        )
        inputTensor.use { pixelValues ->
            encoder.run(mapOf(encoderInputName to pixelValues)).use { encoderResult ->
                val hiddenValue = encoderResult.get(0).value
                    ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 编码器没有输出")
                @Suppress("UNCHECKED_CAST")
                val hiddenRows = hiddenValue as? Array<Array<FloatArray>>
                    ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 编码器输出格式不符合预期")
                val sequenceLength = hiddenRows.firstOrNull()?.size ?: 0
                val hiddenSize = hiddenRows.firstOrNull()?.firstOrNull()?.size ?: 0
                if (sequenceLength <= 0 || hiddenSize <= 0) {
                    throw OcrFailure("ENGINE_ERROR", "MangaOCR 编码器输出为空")
                }
                val flattened = FloatArray(sequenceLength * hiddenSize)
                for (step in 0 until sequenceLength) {
                    val row = hiddenRows.firstOrNull()?.getOrNull(step) ?: continue
                    System.arraycopy(
                        row,
                        0,
                        flattened,
                        step * hiddenSize,
                        minOf(hiddenSize, row.size),
                    )
                }
                val hiddenTensor = OnnxTensor.createTensor(
                    OcrRuntime.environment,
                    directFloatBuffer(flattened),
                    longArrayOf(1, sequenceLength.toLong(), hiddenSize.toLong()),
                )
                hiddenTensor.use { hidden ->
                    return decode(hidden, decoder, isCancelled)
                }
            }
        }
    }

    private fun decode(
        hidden: OnnxTensor,
        decoder: OrtSession,
        isCancelled: () -> Boolean,
    ): RecognizedText {
        val ids = LongArray(MAX_TOKENS + 1)
        ids[0] = CLS_ID.toLong()
        var length = 1
        val text = StringBuilder()
        var confidenceSum = 0f
        var confidenceCount = 0
        while (length <= MAX_TOKENS) {
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            val idsTensor = OnnxTensor.createTensor(
                OcrRuntime.environment,
                directLongBuffer(ids.copyOf(length)),
                longArrayOf(1, length.toLong()),
            )
            var nextId = SEP_ID
            idsTensor.use { inputIds ->
                decoder.run(
                    mapOf(
                        decoderInputIdsName to inputIds,
                        decoderHiddenName to hidden,
                    ),
                ).use { result ->
                    val value = result.get(0).value
                        ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 解码器没有输出")
                    @Suppress("UNCHECKED_CAST")
                    val logits = value as? Array<Array<FloatArray>>
                        ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 解码器输出格式不符合预期")
                    val steps = logits.firstOrNull()
                        ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 解码器输出为空")
                    val last = steps.getOrNull(length - 1)
                        ?: steps.lastOrNull()
                        ?: throw OcrFailure("ENGINE_ERROR", "MangaOCR 解码器时间步为空")
                    val prediction = argmaxWithConfidence(last)
                    nextId = prediction.first
                    if (nextId > MASK_ID && prediction.second.isFinite()) {
                        confidenceSum += prediction.second
                        confidenceCount++
                    }
                }
            }
            if (nextId == SEP_ID) break
            if (nextId > MASK_ID && nextId < tokens.size) {
                val token = tokens[nextId]
                text.append(if (token.startsWith("##")) token.substring(2) else token)
            }
            ids[length] = nextId.toLong()
            length++
        }
        return RecognizedText(
            text = text.toString().trim(),
            confidence = if (confidenceCount == 0) 0f else confidenceSum / confidenceCount,
        )
    }

    private fun argmaxWithConfidence(logits: FloatArray): Pair<Int, Float> {
        if (logits.isEmpty()) return SEP_ID to 0f
        var bestIndex = 0
        var bestValue = logits[0]
        for (index in 1 until logits.size) {
            if (logits[index] > bestValue) {
                bestValue = logits[index]
                bestIndex = index
            }
        }
        var max = logits[0]
        for (value in logits) if (value > max) max = value
        var sum = 0.0
        for (value in logits) sum += exp((value - max).toDouble())
        val confidence = if (sum > 0.0) (1.0 / sum).toFloat() else 0f
        return bestIndex to confidence
    }

    private fun preprocess224(crop: Bitmap): FloatArray {
        val scaled = if (crop.width == IMAGE_SIZE && crop.height == IMAGE_SIZE) {
            crop
        } else {
            Bitmap.createScaledBitmap(crop, IMAGE_SIZE, IMAGE_SIZE, true)
        }
        try {
            val pixels = IntArray(IMAGE_SIZE * IMAGE_SIZE)
            scaled.getPixels(pixels, 0, IMAGE_SIZE, 0, 0, IMAGE_SIZE, IMAGE_SIZE)
            val plane = IMAGE_SIZE * IMAGE_SIZE
            val output = FloatArray(3 * plane)
            for (index in 0 until plane) {
                val pixel = pixels[index]
                val red = (pixel ushr 16) and 0xFF
                val green = (pixel ushr 8) and 0xFF
                val blue = pixel and 0xFF
                // manga-ocr's image processor converts to L (BT.601) and then
                // back to RGB before normalization.
                val gray = (red * 0.299f + green * 0.587f + blue * 0.114f) / 255f
                val normalized = (gray - 0.5f) / 0.5f
                output[index] = normalized
                output[plane + index] = normalized
                output[2 * plane + index] = normalized
            }
            return output
        } finally {
            if (scaled !== crop && !scaled.isRecycled) scaled.recycle()
        }
    }

    private fun crop(bitmap: Bitmap, rect: MangaRect): Bitmap? {
        val left = rect.left.coerceIn(0, bitmap.width - 1)
        val top = rect.top.coerceIn(0, bitmap.height - 1)
        val right = rect.right.coerceIn(left + 1, bitmap.width)
        val bottom = rect.bottom.coerceIn(top + 1, bitmap.height)
        if (right - left < 2 || bottom - top < 2) return null
        return try {
            Bitmap.createBitmap(bitmap, left, top, right - left, bottom - top)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun sanitizeText(value: String): String {
        val cleaned = StringBuilder(value.length)
        for (character in value) {
            when {
                character == '�' -> Unit
                character.code < 0x20 && character != '\n' && character != '\t' -> Unit
                character.code == 0x7F -> Unit
                else -> cleaned.append(character)
            }
        }
        return cleaned.toString().trim()
    }

    private fun hasReadableCharacter(text: String): Boolean =
        text.any { it.isLetterOrDigit() }

    private fun directFloatBuffer(values: FloatArray): FloatBuffer {
        val buffer = ByteBuffer.allocateDirect(values.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(values)
        buffer.flip()
        return buffer
    }

    private fun directLongBuffer(values: LongArray): LongBuffer {
        val buffer = ByteBuffer.allocateDirect(values.size * Long.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asLongBuffer()
        buffer.put(values)
        buffer.flip()
        return buffer
    }

    private fun pickName(names: Set<String>, vararg candidates: String): String {
        for (candidate in candidates) if (candidate in names) return candidate
        return names.firstOrNull() ?: candidates.first()
    }

    /**
     * Manga pages read top-to-bottom in horizontal tiers, then right-to-left
     * inside each tier. The tier split keeps a lower panel from being consumed
     * before an upper panel merely because its columns are further right.
     */
    private fun sortVerticalBlocks(blocks: List<NativeOcrBlock>): List<NativeOcrBlock> {
        if (blocks.size <= 1) return blocks
        val thicknesses = blocks.map {
            minOf(it.right - it.left, it.bottom - it.top).coerceAtLeast(1)
        }.sorted()
        val median = if (thicknesses.size % 2 == 1) {
            thicknesses[thicknesses.size / 2].toFloat()
        } else {
            (thicknesses[thicknesses.size / 2 - 1] + thicknesses[thicknesses.size / 2]) / 2f
        }
        val gapThreshold = (median * 0.5f).roundToInt().coerceAtLeast(1)
        val bands = mutableListOf<MutableList<NativeOcrBlock>>()
        var current = mutableListOf<NativeOcrBlock>()
        var currentBottom = Int.MIN_VALUE
        val sorted = blocks.sortedWith(compareBy({ it.top }, { it.left }))
        for (block in sorted) {
            if (current.isEmpty()) {
                current += block
                currentBottom = block.bottom
                continue
            }
            val gap = block.top - currentBottom
            if (gap >= gapThreshold) {
                bands += current
                current = mutableListOf(block)
                currentBottom = block.bottom
            } else {
                current += block
                currentBottom = maxOf(currentBottom, block.bottom)
            }
        }
        if (current.isNotEmpty()) bands += current
        return bands.flatMap { band ->
            val columns = mutableListOf<MutableList<NativeOcrBlock>>()
            val ordered = band.sortedWith(
                compareByDescending<NativeOcrBlock> { (it.left + it.right) / 2f }
                    .thenBy { it.top },
            )
            for (block in ordered) {
                val center = (block.left + block.right) / 2f
                val existing = columns.firstOrNull { column ->
                    val columnCenter = column.map { (it.left + it.right) / 2f }.average()
                    abs(columnCenter - center) <=
                        maxOf(8f, column.maxOf { (it.right - it.left) }.toFloat() * 0.75f)
                }
                if (existing == null) {
                    columns += mutableListOf(block)
                } else {
                    existing += block
                }
            }
            columns.sortedByDescending { column ->
                column.map { (it.left + it.right) / 2f }.average()
            }.flatMap { column -> column.sortedBy { it.top } }
        }
    }

    private data class RecognizedText(val text: String, val confidence: Float)
    private data class RecognizedChunk(val cropIndex: Int, val result: RecognizedText)

    companion object {
        private const val PAD_ID = 0
        private const val CLS_ID = 2
        private const val SEP_ID = 3
        private const val MASK_ID = 4
        private const val IMAGE_SIZE = 224
        private const val MAX_TOKENS = 48
        private const val MIN_BUBBLE_GAP = 10
        private const val MAX_BUBBLE_GAP = 24
        private const val MIN_CROP_PADDING = 4
        private const val MAX_CROP_PADDING = 10
        private const val MIN_BUBBLE_CONFIDENCE = 0.10f
    }
}
