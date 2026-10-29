/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: PP-OCRv5 horizontal recognition plus optional
 * MangaOCR vertical routing, owned sessions instead of Hilt singletons, no
 * overlay support, and image decoding/EXIF scaling is done in this plugin.
 */
package com.rikai.ocr

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.SystemClock
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

internal data class NativeOcrBlock(
    val text: String,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
    val confidence: Float,
    val orientation: String,
    val points: List<Double>,
)

internal data class NativeOcrResult(
    val engine: String,
    val elapsedMs: Long,
    val width: Int,
    val height: Int,
    val blocks: List<NativeOcrBlock>,
)

internal object OcrRuntime {
    /**
     * Application-scoped ONNX Runtime environment. Never close this from an
     * engine; the next engine/session may still be using it.
     */
    val environment: OrtEnvironment by lazy { OrtEnvironment.getEnvironment() }
}

internal class PaddleOcrEngine {
    private var detSession: OrtSession? = null
    private var recSession: OrtSession? = null
    private var dictionary: CtcDictionary? = null
    private var detInputName: String = ""
    private var recInputName: String = ""
    private var loadedDetPath: String? = null
    private var loadedRecPath: String? = null
    private var loadedKeysPath: String? = null
    private val manga = MangaOcrRecognizer()
    private val docOrientation = DocOrientationRecognizer()
    private val textLineOrientation = TextLineOrientationRecognizer()
    private var mangaError: String? = null

    @Synchronized
    fun initialize(
        detPath: String,
        recPath: String,
        keysPath: String,
        mangaEncoderPath: String? = null,
        mangaDecoderPath: String? = null,
        mangaVocabPath: String? = null,
        docOrientationPath: String? = null,
        textLineOrientationPath: String? = null,
    ): Map<String, Any> {
        val detFile = File(detPath)
        val recFile = File(recPath)
        val keysFile = File(keysPath)
        for (file in listOf(detFile, recFile, keysFile)) {
            if (!file.isFile || file.length() == 0L) {
                throw OcrFailure("MODEL_MISSING", "OCR 模型文件不存在：${file.name}")
            }
        }
        val absoluteDet = detFile.absolutePath
        val absoluteRec = recFile.absolutePath
        val absoluteKeys = keysFile.absolutePath
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)

        val parsedKeys = CtcDictionary.load(keysFile)
        val det = detSession
        val rec = recSession
        val keys = dictionary
        val paddleReused = det != null && rec != null && keys != null &&
            loadedDetPath == absoluteDet &&
            loadedRecPath == absoluteRec &&
            loadedKeysPath == absoluteKeys
        if (!paddleReused) {
            closePaddleSessions()
            try {
                val options = OrtSession.SessionOptions()
                try {
                    options.setIntraOpNumThreads(threads)
                    options.setInterOpNumThreads(1)
                    val newDet = OcrRuntime.environment.createSession(absoluteDet, options)
                    val newRec = try {
                        OcrRuntime.environment.createSession(absoluteRec, options)
                    } catch (error: Throwable) {
                        newDet.close()
                        throw error
                    }
                    detSession = newDet
                    recSession = newRec
                    dictionary = parsedKeys
                    detInputName = newDet.inputNames.first()
                    recInputName = newRec.inputNames.first()
                    loadedDetPath = absoluteDet
                    loadedRecPath = absoluteRec
                    loadedKeysPath = absoluteKeys
                } finally {
                    options.close()
                }
            } catch (error: OutOfMemoryError) {
                closePaddleSessions()
                throw OcrFailure("OOM", "加载 OCR 模型时内存不足")
            } catch (error: Throwable) {
                closePaddleSessions()
                throw OcrFailure("MODEL_INVALID", "无法加载 OCR 模型：${error.message}")
            }
        }

        // Optional vertical models are loaded independently. A missing or
        // broken MangaOCR file must never disable the working horizontal OCR;
        // vertical mode reports the specific error when the user selects it.
        var mangaConfigured = false
        var mangaReused = false
        mangaError = if (
            mangaEncoderPath.isNullOrBlank() ||
            mangaDecoderPath.isNullOrBlank() ||
            mangaVocabPath.isNullOrBlank()
        ) {
            manga.close()
            null
        } else {
            mangaConfigured = true
            try {
                val info = manga.initialize(mangaEncoderPath, mangaDecoderPath, mangaVocabPath)
                mangaReused = info?.get("reused") == true
                if (!manga.isReady()) "MangaOCR 模型文件不完整" else null
            } catch (error: OcrFailure) {
                error.message
            } catch (error: Throwable) {
                error.message ?: "MangaOCR 模型加载失败"
            }
        }
        docOrientation.initialize(docOrientationPath)
        textLineOrientation.initialize(textLineOrientationPath)

        val activeDet = detSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val activeRec = recSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val activeKeys = dictionary ?: throw OcrFailure("ENGINE_ERROR", "OCR 字符表尚未加载")
        return readiness(
            det = activeDet,
            rec = activeRec,
            keys = activeKeys,
            threads = threads,
            reused = paddleReused && (!mangaConfigured || mangaReused),
        )
    }

    private fun readiness(
        det: OrtSession,
        rec: OrtSession,
        keys: CtcDictionary,
        threads: Int,
        reused: Boolean,
    ): Map<String, Any> = mapOf(
        "engine" to "paddle_v5",
        "detInput" to det.inputNames.first(),
        "recInput" to rec.inputNames.first(),
        "keys" to keys.keys.size,
        "threads" to threads,
        "reused" to reused,
        "mangaReady" to manga.isReady(),
        "mangaError" to (mangaError ?: ""),
        "docOrientationReady" to docOrientation.isReady(),
        "textLineOrientationReady" to textLineOrientation.isReady(),
        "manga" to manga.readiness(),
    )

    @Synchronized
    fun recognize(
        imagePath: String,
        mode: String,
        onProgress: (stage: String, current: Int, total: Int) -> Unit,
        isCancelled: () -> Boolean,
    ): NativeOcrResult {
        if (mode != "auto" && mode != "horizontal" && mode != "vertical") {
            throw OcrFailure("UNSUPPORTED_MODE", "不支持的识别模式：$mode")
        }
        if (mode == "vertical" && !manga.isReady()) {
            throw if (!mangaError.isNullOrBlank()) {
                OcrFailure("MODEL_INVALID", "MangaOCR 模型无法使用：$mangaError")
            } else {
                OcrFailure(
                    "MODEL_MISSING",
                    "竖向识别需要先在「OCR 模型」中下载 MangaOCR 模型",
                )
            }
        }
        val det = detSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val rec = recSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val keys = dictionary ?: throw OcrFailure("ENGINE_ERROR", "OCR 字符表尚未加载")
        val started = SystemClock.elapsedRealtime()
        val decoded = decodeBitmap(imagePath)
        var activeBitmap = decoded
        try {
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            val docVerticalHint = mode != "horizontal" && docOrientation.isVerticalHint(activeBitmap)
            onProgress("detect", 0, 1)
            var quads = detectQuads(activeBitmap, det)
            onProgress("detect", 1, 1)
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            val useVertical = when (mode) {
                "vertical" -> true
                "auto" -> docVerticalHint || TextLayoutHeuristic.isVertical(quads)
                else -> false
            }
            if (!useVertical &&
                textLineOrientation.isReady() &&
                textLineOrientation.shouldRotate180(activeBitmap, quads)
            ) {
                val rotated = rotate180(activeBitmap)
                if (rotated != null) {
                    activeBitmap = rotated
                    onProgress("detect", 0, 1)
                    quads = detectQuads(activeBitmap, det)
                    onProgress("detect", 1, 1)
                    if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
                }
            }
            if (useVertical && manga.isReady()) {
                val blocks = manga.recognize(
                    bitmap = activeBitmap,
                    quads = quads,
                    onProgress = onProgress,
                    isCancelled = isCancelled,
                )
                onProgress("done", 1, 1)
                return NativeOcrResult(
                    engine = "manga_ocr",
                    elapsedMs = SystemClock.elapsedRealtime() - started,
                    width = activeBitmap.width,
                    height = activeBitmap.height,
                    blocks = blocks,
                )
            }
            if (mode == "vertical" && !manga.isReady()) {
                throw OcrFailure(
                    "MODEL_MISSING",
                    "竖向识别需要先在「OCR 模型」中下载 MangaOCR 模型",
                )
            }
            if (quads.isEmpty()) {
                return NativeOcrResult(
                    engine = "paddle_v5",
                    elapsedMs = SystemClock.elapsedRealtime() - started,
                    width = activeBitmap.width,
                    height = activeBitmap.height,
                    blocks = emptyList(),
                )
            }

            val ordered = orderQuads(quads)
            val blocks = mutableListOf<NativeOcrBlock>()
            ordered.forEachIndexed { index, quad ->
                if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
                recognizeQuad(activeBitmap, quad, rec, keys)?.let { blocks.add(it) }
                onProgress("recognize", index + 1, ordered.size)
            }
            val orderedBlocks = orderBlocks(blocks)
            onProgress("done", 1, 1)
            return NativeOcrResult(
                engine = "paddle_v5",
                elapsedMs = SystemClock.elapsedRealtime() - started,
                width = activeBitmap.width,
                height = activeBitmap.height,
                blocks = orderedBlocks,
            )
        } finally {
            if (activeBitmap !== decoded && !activeBitmap.isRecycled) {
                activeBitmap.recycle()
            }
            if (!decoded.isRecycled) decoded.recycle()
        }
    }

    @Synchronized
    fun close() {
        closePaddleSessions()
        manga.close()
        docOrientation.close()
        textLineOrientation.close()
    }

    private fun closePaddleSessions() {
        runCatching { detSession?.close() }
        runCatching { recSession?.close() }
        detSession = null
        recSession = null
        dictionary = null
        loadedDetPath = null
        loadedRecPath = null
        loadedKeysPath = null
    }

    private fun detectQuads(bitmap: Bitmap, session: OrtSession): List<DBPostprocessor.Quad> {
        val plan = PaddleDetectionSizing.plan(bitmap.width, bitmap.height)
        val resized = if (plan.resized) {
            Bitmap.createScaledBitmap(bitmap, plan.targetWidth, plan.targetHeight, true)
        } else {
            bitmap
        }
        try {
            val input = bitmapToNchw(
                resized,
                DET_MEAN,
                DET_STD,
                paddedWidth = resized.width,
                padZero = false,
            )
            val tensor = OnnxTensor.createTensor(
                OcrRuntime.environment,
                directBuffer(input),
                longArrayOf(1, 3, resized.height.toLong(), resized.width.toLong()),
            )
            tensor.use {
                session.run(mapOf(detInputName to it)).use { result ->
                    @Suppress("UNCHECKED_CAST")
                    val output = result.get(0).value as? Array<Array<Array<FloatArray>>>
                        ?: throw OcrFailure("ENGINE_ERROR", "OCR 检测输出格式不符合预期")
                    val probMap = output.firstOrNull()?.firstOrNull()
                        ?: throw OcrFailure("ENGINE_ERROR", "OCR 检测输出为空")
                    val outputWidth = probMap.firstOrNull()?.size ?: 0
                    val outputHeight = probMap.size
                    if (outputWidth <= 0 || outputHeight <= 0) return emptyList()
                    val scaleX = bitmap.width.toFloat() / outputWidth
                    val scaleY = bitmap.height.toFloat() / outputHeight
                    return DBPostprocessor.extractQuads(
                        probMap = probMap,
                        scaleX = scaleX,
                        scaleY = scaleY,
                        binThresh = DET_PROB_THRESHOLD,
                        scoreThresh = DET_BOX_THRESHOLD,
                        unclipRatio = DET_UNCLIP_RATIO,
                    )
                }
            }
        } finally {
            if (resized !== bitmap && !resized.isRecycled) resized.recycle()
        }
    }

    private fun recognizeQuad(
        source: Bitmap,
        quad: DBPostprocessor.Quad,
        session: OrtSession,
        dictionary: CtcDictionary,
    ): NativeOcrBlock? {
        val cropQuad = DBPostprocessor.fitRecognitionCropQuad(quad, source.width, source.height)
            ?: return null
        val points = cropQuad.cornerPoints()
        val cropSize = PaddleRotateCrop.keptCropSize(points, source.width, source.height)
            ?: return null
        val bounds = PaddleRotateCrop.sourceBounds(points, source.width, source.height)
        val regionWidth = bounds[2] - bounds[0]
        val regionHeight = bounds[3] - bounds[1]
        if (regionWidth <= 0 || regionHeight <= 0) return null

        val region = IntArray(regionWidth * regionHeight)
        source.getPixels(region, 0, regionWidth, bounds[0], bounds[1], regionWidth, regionHeight)
        val warped = PaddleRotateCrop.warp(
            source = region,
            sourceWidth = regionWidth,
            sourceHeight = regionHeight,
            originX = bounds[0],
            originY = bounds[1],
            points = points,
            width = cropSize[0],
            height = cropSize[1],
        )
        var crop = Bitmap.createBitmap(cropSize[0], cropSize[1], Bitmap.Config.ARGB_8888)
        crop.setPixels(warped, 0, cropSize[0], 0, 0, cropSize[0], cropSize[1])
        var orientation = "horizontal"
        try {
            if (crop.height > crop.width * 1.5f) {
                val rotated = rotateBitmap(crop, -90f) ?: return null
                crop.recycle()
                crop = rotated
                orientation = "vertical"
            }
            val naturalWidth = ceil(
                RECOGNITION_HEIGHT.toDouble() * crop.width / crop.height,
            ).toInt().coerceAtLeast(RECOGNITION_MIN_WIDTH)
            val targetWidth = naturalWidth.coerceAtMost(RECOGNITION_MAX_WIDTH)
            val tensorWidth = max(RECOGNITION_BASE_WIDTH, targetWidth)
            val resized = Bitmap.createScaledBitmap(
                crop,
                targetWidth,
                RECOGNITION_HEIGHT,
                true,
            )
            try {
                val input = bitmapToNchw(
                    resized,
                    REC_MEAN,
                    REC_STD,
                    paddedWidth = tensorWidth,
                    padZero = true,
                )
                val tensor = OnnxTensor.createTensor(
                    OcrRuntime.environment,
                    directBuffer(input),
                    longArrayOf(1, 3, RECOGNITION_HEIGHT.toLong(), tensorWidth.toLong()),
                )
                tensor.use {
                    session.run(mapOf(recInputName to it)).use { result ->
                        @Suppress("UNCHECKED_CAST")
                        val output = result.get(0).value as? Array<Array<FloatArray>>
                            ?: throw OcrFailure("ENGINE_ERROR", "OCR 识别输出格式不符合预期")
                        val decoded = dictionary.decode(output.getOrNull(0) ?: return null)
                        val text = decoded.text.trim()
                        if (text.isEmpty() || decoded.score < MIN_RECOGNITION_SCORE) return null
                        val box = quad.axisAlignedBounds()
                        val left = box[0].coerceIn(0, source.width)
                        val top = box[1].coerceIn(0, source.height)
                        val right = box[2].coerceIn(0, source.width)
                        val bottom = box[3].coerceIn(0, source.height)
                        if (right <= left || bottom <= top) return null
                        return NativeOcrBlock(
                            text = text,
                            left = left,
                            top = top,
                            right = right,
                            bottom = bottom,
                            confidence = decoded.score,
                            orientation = orientation,
                            points = points.toList().map { value -> value.toDouble() },
                        )
                    }
                }
            } finally {
                if (!resized.isRecycled) resized.recycle()
            }
        } finally {
            if (!crop.isRecycled) crop.recycle()
        }
    }

    private fun decodeBitmap(path: String): Bitmap {
        val file = File(path)
        if (!file.isFile || file.length() == 0L) {
            throw OcrFailure("IMAGE_DECODE_FAILED", "图片不存在：$path")
        }
        try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                throw OcrFailure("IMAGE_DECODE_FAILED", "无法读取图片尺寸")
            }
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_IMAGE_SIDE) {
                sample *= 2
            }
            val options = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            var bitmap = BitmapFactory.decodeFile(path, options)
                ?: throw OcrFailure("IMAGE_DECODE_FAILED", "无法解码图片")
            bitmap = applyExifOrientation(path, bitmap)
            val longest = max(bitmap.width, bitmap.height)
            if (longest > MAX_IMAGE_SIDE) {
                val scale = MAX_IMAGE_SIDE.toFloat() / longest
                val targetWidth = (bitmap.width * scale).roundToInt().coerceAtLeast(1)
                val targetHeight = (bitmap.height * scale).roundToInt().coerceAtLeast(1)
                val scaled = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
                if (scaled !== bitmap) bitmap.recycle()
                bitmap = scaled
            }
            return bitmap
        } catch (error: OutOfMemoryError) {
            throw OcrFailure("OOM", "图片过大，内存不足")
        }
    }

    private fun applyExifOrientation(path: String, bitmap: Bitmap): Bitmap {
        val orientation = runCatching {
            ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.setRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        if (matrix.isIdentity) return bitmap
        return try {
            val rotated = Bitmap.createBitmap(
                bitmap,
                0,
                0,
                bitmap.width,
                bitmap.height,
                matrix,
                true,
            )
            if (rotated !== bitmap) bitmap.recycle()
            rotated
        } catch (_: OutOfMemoryError) {
            throw OcrFailure("OOM", "图片旋转时内存不足")
        }
    }

    private fun rotate180(bitmap: Bitmap): Bitmap? = try {
        val matrix = Matrix().apply { postRotate(180f) }
        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    } catch (_: OutOfMemoryError) {
        throw OcrFailure("OOM", "图片旋转时内存不足")
    } catch (_: Exception) {
        null
    }

    private fun rotateBitmap(bitmap: Bitmap, degrees: Float): Bitmap? = try {
        val matrix = Matrix().apply { postRotate(degrees) }
        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    } catch (_: Exception) {
        null
    }

    private fun bitmapToNchw(
        bitmap: Bitmap,
        mean: FloatArray,
        std: FloatArray,
        paddedWidth: Int,
        padZero: Boolean,
    ): FloatArray {
        val width = bitmap.width
        val height = bitmap.height
        require(width <= paddedWidth)
        val planeSize = paddedWidth * height
        val output = FloatArray(3 * planeSize)
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        for (y in 0 until height) {
            val rowOffset = y * paddedWidth
            for (x in 0 until width) {
                val pixel = pixels[y * width + x]
                val r = ((pixel ushr 16) and 0xFF) / 255f
                val g = ((pixel ushr 8) and 0xFF) / 255f
                val b = (pixel and 0xFF) / 255f
                val position = rowOffset + x
                output[position] = (b - mean[0]) / std[0]
                output[planeSize + position] = (g - mean[1]) / std[1]
                output[2 * planeSize + position] = (r - mean[2]) / std[2]
            }
        }
        // The remaining columns are already normalized zero (the neutral
        // padding value for PaddleOCR's 0.5/0.5 normalization).
        if (!padZero) {
            // No-op; kept explicit for call sites that expect no padding.
        }
        return output
    }

    private fun directBuffer(values: FloatArray): FloatBuffer {
        val buffer = ByteBuffer.allocateDirect(values.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(values)
        buffer.flip()
        return buffer
    }

    private fun orderQuads(quads: List<DBPostprocessor.Quad>): List<DBPostprocessor.Quad> =
        quads.sortedWith(
            compareBy({ it.centerY }, { it.centerX }),
        )

    private fun orderBlocks(blocks: List<NativeOcrBlock>): List<NativeOcrBlock> {
        if (blocks.size <= 1) return blocks
        val averageHeight = blocks.map { (it.bottom - it.top).coerceAtLeast(1) }
            .average().toFloat()
        val lineThreshold = max(8f, averageHeight * 0.65f)
        val lines = mutableListOf<MutableList<NativeOcrBlock>>()
        for (block in blocks.sortedWith(compareBy({ it.top }, { it.left }))) {
            val centerY = (block.top + block.bottom) / 2f
            val line = lines.firstOrNull { existing ->
                abs(existing.map { (it.top + it.bottom) / 2f }.average() - centerY) <= lineThreshold
            }
            if (line == null) {
                lines.add(mutableListOf(block))
            } else {
                line.add(block)
            }
        }
        return lines
            .sortedBy { line -> line.minOf { it.top } }
            .flatMap { line -> line.sortedBy { it.left } }
    }

    companion object {
        private const val MAX_IMAGE_SIDE = 2048
        private const val DET_PROB_THRESHOLD = 0.3f
        private const val DET_BOX_THRESHOLD = 0.6f
        private const val DET_UNCLIP_RATIO = 1.6f
        private const val RECOGNITION_HEIGHT = 48
        private const val RECOGNITION_MIN_WIDTH = 8
        private const val RECOGNITION_BASE_WIDTH = 320
        private const val RECOGNITION_MAX_WIDTH = 3200
        private const val MIN_RECOGNITION_SCORE = 0.15f
        private val DET_MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
        private val DET_STD = floatArrayOf(0.229f, 0.224f, 0.225f)
        private val REC_MEAN = floatArrayOf(0.5f, 0.5f, 0.5f)
        private val REC_STD = floatArrayOf(0.5f, 0.5f, 0.5f)
    }
}
