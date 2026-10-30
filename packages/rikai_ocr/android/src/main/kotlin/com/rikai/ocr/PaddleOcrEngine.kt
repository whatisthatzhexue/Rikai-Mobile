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
import kotlin.math.atan2
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

private data class OcrCandidate(
    val engine: String,
    val blocks: List<NativeOcrBlock>,
    val score: Double,
    val width: Int,
    val height: Int,
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
    private var mangaEncoderPath: String? = null
    private var mangaDecoderPath: String? = null
    private var mangaVocabPath: String? = null
    private var mangaAvailable = false
    private var docOrientationPath: String? = null
    private var textLineOrientationPath: String? = null
    private var docOrientationAvailable = false
    private var textLineOrientationAvailable = false
    private var docOrientationLoadFailed = false
    private var textLineOrientationLoadFailed = false
    private var threadCount = 1

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
        threadCount = threads

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

        // Optional models are registered here, but their native sessions are
        // created lazily. Horizontal-only use must not pay the MangaOCR
        // encoder/decoder load cost, and a missing/broken optional model must
        // never disable the working horizontal OCR.
        if (detSession == null || recSession == null || dictionary == null) {
            throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        }
        configureOptionalModels(
            mangaEncoderPath = mangaEncoderPath,
            mangaDecoderPath = mangaDecoderPath,
            mangaVocabPath = mangaVocabPath,
            docOrientationPath = docOrientationPath,
            textLineOrientationPath = textLineOrientationPath,
        )
        return readiness(reused = paddleReused)
    }

    /**
     * Loads the optional models required by [mode] without decoding an image.
     * Used by the Dart layer to warm the session while the photo-set page is
     * idle. Failures are reflected in readiness rather than thrown.
     */
    @Synchronized
    fun prepare(mode: String): Map<String, Any> {
        if (mode != "auto" && mode != "horizontal" && mode != "vertical") {
            throw OcrFailure("UNSUPPORTED_MODE", "不支持的识别模式：$mode")
        }
        if (mode != "horizontal") ensureMangaLoaded()
        if (mode == "auto") {
            ensureDocOrientationLoaded()
            ensureTextLineOrientationLoaded()
        }
        return readiness(reused = true)
    }

    private fun configureOptionalModels(
        mangaEncoderPath: String?,
        mangaDecoderPath: String?,
        mangaVocabPath: String?,
        docOrientationPath: String?,
        textLineOrientationPath: String?,
    ) {
        val nextManga = if (
            mangaEncoderPath.isNullOrBlank() ||
            mangaDecoderPath.isNullOrBlank() ||
            mangaVocabPath.isNullOrBlank()
        ) {
            null
        } else {
            Triple(mangaEncoderPath, mangaDecoderPath, mangaVocabPath)
        }
        val currentManga = if (
            this.mangaEncoderPath == null ||
            this.mangaDecoderPath == null ||
            this.mangaVocabPath == null
        ) {
            null
        } else {
            Triple(this.mangaEncoderPath!!, this.mangaDecoderPath!!, this.mangaVocabPath!!)
        }
        if (nextManga != currentManga) {
            manga.close()
            mangaError = null
        }
        this.mangaEncoderPath = nextManga?.first
        this.mangaDecoderPath = nextManga?.second
        this.mangaVocabPath = nextManga?.third
        mangaAvailable = nextManga != null &&
            listOf(nextManga.first, nextManga.second, nextManga.third).all(::isReadableFile)
        if (nextManga != null && !mangaAvailable && mangaError.isNullOrBlank()) {
            mangaError = "MangaOCR 模型文件不完整"
        }
        // Re-initialization (for example after returning from model settings)
        // gets one fresh lazy-load attempt even when the paths are unchanged.
        if (nextManga != null && mangaAvailable && !manga.isReady()) {
            mangaError = null
        }

        val nextDoc = docOrientationPath?.takeIf { it.isNotBlank() }
        if (this.docOrientationPath != nextDoc) {
            docOrientation.close()
            docOrientationLoadFailed = false
        }
        this.docOrientationPath = nextDoc
        docOrientationAvailable = nextDoc != null && isReadableFile(nextDoc)
        if (docOrientationAvailable) docOrientationLoadFailed = false

        val nextTextLine = textLineOrientationPath?.takeIf { it.isNotBlank() }
        if (this.textLineOrientationPath != nextTextLine) {
            textLineOrientation.close()
            textLineOrientationLoadFailed = false
        }
        this.textLineOrientationPath = nextTextLine
        textLineOrientationAvailable = nextTextLine != null && isReadableFile(nextTextLine)
        if (textLineOrientationAvailable) textLineOrientationLoadFailed = false
    }

    private fun isReadableFile(path: String): Boolean {
        val file = File(path)
        return file.isFile && file.length() > 0L
    }

    private fun ensureMangaLoaded(): Boolean {
        if (!mangaAvailable) return false
        if (manga.isReady()) return true
        if (!mangaError.isNullOrBlank()) return false
        val encoder = mangaEncoderPath ?: return false
        val decoder = mangaDecoderPath ?: return false
        val vocab = mangaVocabPath ?: return false
        return try {
            manga.initialize(encoder, decoder, vocab)
            if (manga.isReady()) {
                true
            } else {
                mangaError = "MangaOCR 模型文件不完整"
                false
            }
        } catch (error: OcrFailure) {
            mangaError = error.message
            false
        } catch (error: Throwable) {
            mangaError = error.message ?: "MangaOCR 模型加载失败"
            false
        }
    }

    private fun ensureDocOrientationLoaded(): Boolean {
        if (!docOrientationAvailable || docOrientationLoadFailed) return false
        if (docOrientation.isReady()) return true
        val path = docOrientationPath ?: return false
        val loaded = docOrientation.initialize(path)
        if (!loaded) docOrientationLoadFailed = true
        return loaded
    }

    private fun ensureTextLineOrientationLoaded(): Boolean {
        if (!textLineOrientationAvailable || textLineOrientationLoadFailed) return false
        if (textLineOrientation.isReady()) return true
        val path = textLineOrientationPath ?: return false
        val loaded = textLineOrientation.initialize(path)
        if (!loaded) textLineOrientationLoadFailed = true
        return loaded
    }

    private fun readiness(reused: Boolean): Map<String, Any> {
        val det = detSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val rec = recSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val keys = dictionary ?: throw OcrFailure("ENGINE_ERROR", "OCR 字符表尚未加载")
        return mapOf(
            "engine" to "paddle_v5",
            "detInput" to det.inputNames.first(),
            "recInput" to rec.inputNames.first(),
            "keys" to keys.keys.size,
            "threads" to threadCount,
            "reused" to reused,
            // `*Ready` remains the compatibility/availability flag used by the
            // photo-set helper. `*Loaded` reports the lazy native session.
            "mangaReady" to mangaAvailable,
            "mangaAvailable" to mangaAvailable,
            "mangaLoaded" to manga.isReady(),
            "mangaError" to (mangaError ?: ""),
            "docOrientationReady" to docOrientationAvailable,
            "docOrientationAvailable" to docOrientationAvailable,
            "docOrientationLoaded" to docOrientation.isReady(),
            "textLineOrientationReady" to textLineOrientationAvailable,
            "textLineOrientationAvailable" to textLineOrientationAvailable,
            "textLineOrientationLoaded" to textLineOrientation.isReady(),
            "manga" to manga.readiness(),
        )
    }

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
        val det = detSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val rec = recSession ?: throw OcrFailure("ENGINE_ERROR", "OCR 模型尚未初始化")
        val keys = dictionary ?: throw OcrFailure("ENGINE_ERROR", "OCR 字符表尚未加载")
        val started = SystemClock.elapsedRealtime()
        val decoded = decodeBitmap(imagePath)
        var activeBitmap = decoded
        try {
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            onProgress("detect", 0, 1)
            var quads = detectQuads(activeBitmap, det)
            onProgress("detect", 1, 1)
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            var orientationCorrected = false

            // A 90/270 page can look like ordinary vertical text after DBNet.
            // Run the document classifier only when the image aspect and box
            // geometry could describe a sideways page; ordinary landscape
            // horizontal pages skip this optional model entirely.
            if (mode == "auto" && shouldCheckDocumentOrientation(activeBitmap, quads)) {
                val corrected = correctDocumentRotation(activeBitmap)
                if (corrected != null) {
                    if (activeBitmap !== decoded) activeBitmap.recycle()
                    activeBitmap = corrected
                    orientationCorrected = true
                    onProgress("detect", 0, 1)
                    quads = detectQuads(activeBitmap, det)
                    onProgress("detect", 1, 1)
                    if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
                }
            }

            var useVertical = when (mode) {
                "vertical" -> true
                "auto" -> TextLayoutHeuristic.isVertical(quads)
                else -> false
            }

            // A phone held diagonally produces a small constant baseline skew.
            // Correct only a moderate horizontal skew; 90/180° pages are
            // handled by the document/text-line classifiers above.
            if (!useVertical && !orientationCorrected) {
                val skew = horizontalSkewDegrees(quads)
                if (skew != null && abs(skew) >= MIN_DESKEW_DEGREES &&
                    abs(skew) <= MAX_DESKEW_DEGREES
                ) {
                    val corrected = rotateBitmap(activeBitmap, -skew)
                    if (corrected != null) {
                        if (activeBitmap !== decoded) activeBitmap.recycle()
                        activeBitmap = corrected
                        onProgress("detect", 0, 1)
                        quads = detectQuads(activeBitmap, det)
                        onProgress("detect", 1, 1)
                        if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
                        useVertical = mode == "vertical" ||
                            (mode == "auto" && TextLayoutHeuristic.isVertical(quads))
                    }
                }
            }
            if (!useVertical &&
                mode == "auto" &&
                ensureTextLineOrientationLoaded() &&
                textLineOrientation.shouldRotate180(activeBitmap, quads)
            ) {
                val rotated = rotate180(activeBitmap)
                if (rotated != null) {
                    if (activeBitmap !== decoded) activeBitmap.recycle()
                    activeBitmap = rotated
                    onProgress("detect", 0, 1)
                    quads = detectQuads(activeBitmap, det)
                    onProgress("detect", 1, 1)
                    if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
                    useVertical = TextLayoutHeuristic.isVertical(quads)
                }
            }
            if (useVertical) {
                val mangaReady = ensureMangaLoaded()
                if (mode == "vertical" && !mangaReady) {
                    throw if (!mangaError.isNullOrBlank()) {
                        OcrFailure("MODEL_INVALID", "MangaOCR 模型无法使用：$mangaError")
                    } else {
                        OcrFailure(
                            "MODEL_MISSING",
                            "竖向识别需要先在「OCR 模型」中下载 MangaOCR 模型",
                        )
                    }
                }

                val candidates = mutableListOf<OcrCandidate>()
                if (mangaReady) {
                    val blocks = manga.recognize(
                        bitmap = activeBitmap,
                        quads = quads,
                        onProgress = onProgress,
                        isCancelled = isCancelled,
                    )
                    candidates.add(
                        OcrCandidate(
                            engine = "manga_ocr",
                            blocks = blocks,
                            score = OcrTextQuality.score(blocks),
                            width = activeBitmap.width,
                            height = activeBitmap.height,
                        ),
                    )
                }
                if (quads.isNotEmpty()) {
                    val paddleBlocks = recognizePaddleQuads(
                        bitmap = activeBitmap,
                        quads = quads,
                        rec = rec,
                        keys = keys,
                        onProgress = onProgress,
                        isCancelled = isCancelled,
                    )
                    candidates.add(
                        OcrCandidate(
                            engine = "paddle_v5",
                            blocks = paddleBlocks,
                            score = OcrTextQuality.score(paddleBlocks),
                            width = activeBitmap.width,
                            height = activeBitmap.height,
                        ),
                    )
                }

                // Dense tategaki pages sometimes read better after rotating the
                // image 90° and letting PaddleOCR's horizontal recognizer look
                // at it. Only pay for those extra passes when both primary
                // candidates look weak; a clean result already wins.
                val bestPrimaryScore = candidates.maxOfOrNull { it.score } ?: 0.0
                if (quads.isNotEmpty() &&
                    bestPrimaryScore < VERTICAL_ROTATION_RETRY_SCORE
                ) {
                    for (degrees in listOf(-90f, 90f)) {
                        if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
                        val rotated = rotateBitmap(activeBitmap, degrees) ?: continue
                        try {
                            onProgress("detect", 0, 1)
                            val rotatedQuads = detectQuads(rotated, det)
                            onProgress("detect", 1, 1)
                            if (rotatedQuads.isEmpty()) continue
                            val rotatedBlocks = recognizePaddleQuads(
                                bitmap = rotated,
                                quads = rotatedQuads,
                                rec = rec,
                                keys = keys,
                                onProgress = onProgress,
                                isCancelled = isCancelled,
                            )
                            candidates.add(
                                OcrCandidate(
                                    engine = "paddle_v5",
                                    blocks = rotatedBlocks,
                                    score = OcrTextQuality.score(rotatedBlocks),
                                    width = rotated.width,
                                    height = rotated.height,
                                ),
                            )
                        } finally {
                            if (!rotated.isRecycled) rotated.recycle()
                        }
                    }
                }

                val nonEmpty = candidates.filter { it.blocks.isNotEmpty() }
                val mangaCandidate = nonEmpty.firstOrNull { it.engine == "manga_ocr" }
                val paddleCandidate = nonEmpty
                    .filter { it.engine == "paddle_v5" }
                    .maxByOrNull { it.score }
                // PaddleOCR's confidence is often slightly higher on clean
                // bubbles; require a clear quality win before replacing the
                // vertical model, so ordinary manga pages stay on MangaOCR.
                val best = when {
                    mangaCandidate == null -> paddleCandidate
                    paddleCandidate == null -> mangaCandidate
                    paddleCandidate.score >
                        mangaCandidate.score + CANDIDATE_SWITCH_MARGIN ->
                        paddleCandidate
                    else -> mangaCandidate
                }
                onProgress("done", 1, 1)
                if (best != null) {
                    return NativeOcrResult(
                        engine = best.engine,
                        elapsedMs = SystemClock.elapsedRealtime() - started,
                        width = best.width,
                        height = best.height,
                        blocks = best.blocks,
                    )
                }
                return NativeOcrResult(
                    engine = "paddle_v5",
                    elapsedMs = SystemClock.elapsedRealtime() - started,
                    width = activeBitmap.width,
                    height = activeBitmap.height,
                    blocks = emptyList(),
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

            val orderedBlocks = recognizePaddleQuads(
                bitmap = activeBitmap,
                quads = quads,
                rec = rec,
                keys = keys,
                onProgress = onProgress,
                isCancelled = isCancelled,
            )
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
        mangaAvailable = false
        mangaError = null
        mangaEncoderPath = null
        mangaDecoderPath = null
        mangaVocabPath = null
        docOrientationAvailable = false
        textLineOrientationAvailable = false
        docOrientationPath = null
        textLineOrientationPath = null
        docOrientationLoadFailed = false
        textLineOrientationLoadFailed = false
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

    private fun recognizePaddleQuads(
        bitmap: Bitmap,
        quads: List<DBPostprocessor.Quad>,
        rec: OrtSession,
        keys: CtcDictionary,
        onProgress: (stage: String, current: Int, total: Int) -> Unit,
        isCancelled: () -> Boolean,
    ): List<NativeOcrBlock> {
        if (quads.isEmpty()) return emptyList()
        val ordered = orderQuads(quads)
        val blocks = mutableListOf<NativeOcrBlock>()
        ordered.forEachIndexed { index, quad ->
            if (isCancelled()) throw OcrFailure("CANCELLED", "已取消识别")
            recognizeQuad(bitmap, quad, rec, keys)?.let { blocks.add(it) }
            onProgress("recognize", index + 1, ordered.size)
        }
        return orderBlocks(blocks)
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

    private fun shouldCheckDocumentOrientation(
        bitmap: Bitmap,
        quads: List<DBPostprocessor.Quad>,
    ): Boolean {
        if (!docOrientationAvailable || quads.isEmpty()) return false
        // Only aspect/layout disagreement is ambiguous:
        //   landscape page + vertical boxes = a portrait page rotated 90°;
        //   portrait page + horizontal boxes = a landscape page rotated 90°.
        // Upright portrait tategaki and upright landscape text skip the model,
        // and square pages are left to DBNet geometry.
        if (bitmap.width == bitmap.height) return false
        val geometryVertical = TextLayoutHeuristic.isVertical(quads)
        return if (bitmap.width > bitmap.height) {
            geometryVertical
        } else {
            !geometryVertical
        }
    }

    /**
     * PP-LCNet labels the clockwise rotation of the input relative to upright,
     * so the corrective rotation is the negative label. Only 90/270 are
     * applied here; 180° horizontal correction stays with the text-line model.
     */
    private fun correctDocumentRotation(bitmap: Bitmap): Bitmap? {
        if (!ensureDocOrientationLoaded()) return null
        val orientation = docOrientation.classify(bitmap) ?: return null
        if (!docOrientation.isConfident(orientation)) return null
        if (orientation.angle != 90 && orientation.angle != 270) return null
        return rotateBitmap(bitmap, -orientation.angle.toFloat())
    }

    /**
     * Median baseline angle of clearly horizontal DBNet boxes. Returns null
     * when there are too few reliable boxes or the angle is an upright/
     * upside-down page rather than a small skew.
     */
    private fun horizontalSkewDegrees(quads: List<DBPostprocessor.Quad>): Float? {
        val angles = quads.mapNotNull { quad ->
            val width = quad.width
            val height = quad.height
            if (width < 20f || width < height * 1.2f) return@mapNotNull null
            val raw = Math.toDegrees(
                atan2(
                    (quad.p1.y - quad.p0.y).toDouble(),
                    (quad.p1.x - quad.p0.x).toDouble(),
                ),
            ).toFloat()
            val normalized = when {
                raw > 90f -> raw - 180f
                raw < -90f -> raw + 180f
                else -> raw
            }
            if (abs(normalized) <= 45f) normalized else null
        }.sorted()
        if (angles.size < 2) return null
        return if (angles.size % 2 == 1) {
            angles[angles.size / 2]
        } else {
            (angles[angles.size / 2 - 1] + angles[angles.size / 2]) / 2f
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
        private const val MIN_DESKEW_DEGREES = 2f
        private const val MAX_DESKEW_DEGREES = 12f
        private const val VERTICAL_ROTATION_RETRY_SCORE = 0.80
        private const val CANDIDATE_SWITCH_MARGIN = 0.04
        private val DET_MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
        private val DET_STD = floatArrayOf(0.229f, 0.224f, 0.225f)
        private val REC_MEAN = floatArrayOf(0.5f, 0.5f, 0.5f)
        private val REC_STD = floatArrayOf(0.5f, 0.5f, 0.5f)
    }
}
