/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: standalone optional PP-LCNet document-orientation
 * classifier. It is only a conservative pre-OCR hint; bbox geometry remains
 * the final routing decision.
 */
package com.rikai.ocr

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.roundToInt

internal data class DocOrientation(
    val angle: Int,
    val confidence: Float,
    val margin: Float,
)

internal class DocOrientationRecognizer {
    private var session: OrtSession? = null
    private var inputName: String = ""
    private var loadedPath: String? = null

    @Synchronized
    fun initialize(path: String?): Boolean {
        if (path.isNullOrBlank()) {
            closeSession()
            return false
        }
        val file = File(path)
        if (!file.isFile || file.length() == 0L) {
            closeSession()
            return false
        }
        val absolute = file.absolutePath
        session?.let { existing ->
            if (loadedPath == absolute) return true
            runCatching { existing.close() }
            session = null
        }
        return try {
            val options = OrtSession.SessionOptions()
            try {
                options.setIntraOpNumThreads(
                    Runtime.getRuntime().availableProcessors().coerceIn(1, 2),
                )
                options.setInterOpNumThreads(1)
                val created = OcrRuntime.environment.createSession(absolute, options)
                session = created
                inputName = created.inputNames.firstOrNull().orEmpty()
                loadedPath = absolute
                inputName.isNotEmpty()
            } finally {
                options.close()
            }
        } catch (_: OutOfMemoryError) {
            closeSession()
            false
        } catch (_: Throwable) {
            closeSession()
            false
        }
    }

    @Synchronized
    fun isReady(): Boolean = session != null

    /**
     * Returns the classifier's best rotation label. The label is the clockwise
     * image rotation relative to upright, so the correction is `-angle`.
     * Low-confidence results are rejected by the caller.
     *
     * The PP-LCNet ONNX outputs logits. Its softmax probability is often only
     * 0.3–0.5 even for a clear page, so we also expose the top-1/top-2 margin.
     */
    @Synchronized
    fun classify(bitmap: Bitmap): DocOrientation? {
        val active = session ?: return null
        val name = inputName
        if (name.isEmpty()) return null
        return try {
            val input = bitmapToInput(bitmap)
            val tensor = OnnxTensor.createTensor(
                OcrRuntime.environment,
                directBuffer(input),
                longArrayOf(1, 3, INPUT_SIZE.toLong(), INPUT_SIZE.toLong()),
            )
            tensor.use {
                active.run(mapOf(name to it)).use { result ->
                    val scores = extractScores(result.get(0).value)
                    if (scores.size != LABEL_ANGLES.size) return null
                    val probabilities = probabilities(scores)
                    if (probabilities.size != scores.size) return null
                    val sorted = scores.indices.sortedByDescending { i -> scores[i] }
                    val best = sorted.firstOrNull() ?: return null
                    val second = sorted.getOrNull(1)
                    val margin = if (second == null) {
                        scores[best]
                    } else {
                        (scores[best] - scores[second]).coerceAtLeast(0f)
                    }
                    DocOrientation(
                        angle = LABEL_ANGLES[best],
                        confidence = probabilities[best],
                        margin = margin,
                    )
                }
            }
        } catch (_: OutOfMemoryError) {
            null
        } catch (_: Throwable) {
            null
        }
    }

    fun isConfident(orientation: DocOrientation): Boolean =
        orientation.confidence >= MIN_VERTICAL_CONFIDENCE ||
            orientation.margin >= MIN_ROTATION_MARGIN

    @Synchronized
    fun close() {
        closeSession()
    }

    private fun closeSession() {
        runCatching { session?.close() }
        session = null
        loadedPath = null
        inputName = ""
    }

    private fun bitmapToInput(bitmap: Bitmap): FloatArray {
        val resized = resizeShort(bitmap, RESIZE_SHORT)
        val cropped = centerCrop(resized, INPUT_SIZE)
        try {
            val width = cropped.width
            val height = cropped.height
            val pixels = IntArray(width * height)
            cropped.getPixels(pixels, 0, width, 0, 0, width, height)
            val plane = width * height
            val output = FloatArray(3 * plane)
            for (i in 0 until plane) {
                val pixel = pixels[i]
                val r = ((pixel ushr 16) and 0xFF) / 255f
                val g = ((pixel ushr 8) and 0xFF) / 255f
                val b = (pixel and 0xFF) / 255f
                output[i] = (r - MEAN[0]) / STD[0]
                output[plane + i] = (g - MEAN[1]) / STD[1]
                output[2 * plane + i] = (b - MEAN[2]) / STD[2]
            }
            return output
        } finally {
            if (cropped !== resized && !cropped.isRecycled) cropped.recycle()
            if (resized !== bitmap && !resized.isRecycled) resized.recycle()
        }
    }

    private fun resizeShort(bitmap: Bitmap, shortSide: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val scale = shortSide.toFloat() / min(width, height).coerceAtLeast(1)
        val newWidth = (width * scale).roundToInt().coerceAtLeast(shortSide)
        val newHeight = (height * scale).roundToInt().coerceAtLeast(shortSide)
        return if (newWidth == width && newHeight == height) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        }
    }

    private fun centerCrop(bitmap: Bitmap, size: Int): Bitmap {
        val x = ((bitmap.width - size) / 2).coerceAtLeast(0)
        val y = ((bitmap.height - size) / 2).coerceAtLeast(0)
        val width = min(size, bitmap.width - x)
        val height = min(size, bitmap.height - y)
        return if (x == 0 && y == 0 && width == bitmap.width && height == bitmap.height) {
            bitmap
        } else {
            Bitmap.createBitmap(bitmap, x, y, width, height)
        }
    }

    private fun probabilities(scores: FloatArray): FloatArray {
        if (scores.isEmpty() || scores.any { !it.isFinite() }) return FloatArray(0)
        val sum = scores.sum()
        if (scores.all { it in 0f..1f } && abs(sum - 1f) <= 0.001f) {
            return FloatArray(scores.size) { scores[it] / sum }
        }
        val max = scores.maxOrNull() ?: 0f
        val exps = FloatArray(scores.size)
        var total = 0.0
        for (i in scores.indices) {
            val value = exp((scores[i] - max).toDouble())
            exps[i] = value.toFloat()
            total += value
        }
        if (total <= 0.0 || !total.isFinite()) {
            return FloatArray(scores.size) { 1f / scores.size }
        }
        return FloatArray(scores.size) { exps[it] / total.toFloat() }
    }

    private fun extractScores(value: Any?): FloatArray = when (value) {
        is FloatArray -> value
        is Array<*> -> if (value.isEmpty()) FloatArray(0) else extractScores(value[0])
        else -> FloatArray(0)
    }

    private fun directBuffer(values: FloatArray): FloatBuffer {
        val buffer = ByteBuffer.allocateDirect(values.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(values)
        buffer.flip()
        return buffer
    }

    companion object {
        private const val RESIZE_SHORT = 256
        private const val INPUT_SIZE = 224
        private const val MIN_VERTICAL_CONFIDENCE = 0.65f
        private const val MIN_ROTATION_MARGIN = 0.35f
        private val LABEL_ANGLES = intArrayOf(0, 90, 180, 270)
        private val MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
        private val STD = floatArrayOf(0.229f, 0.224f, 0.225f)
    }
}
