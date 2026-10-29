/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: optional PP-LCNet 0/180 text-line classifier used
 * to re-run a horizontal page that was photographed upside down.
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

internal class TextLineOrientationRecognizer {
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
     * True when at least two large horizontal line crops are confidently
     * classified as 180°. A single ambiguous line is deliberately ignored to
     * avoid rotating pages with mixed captions or stylised text.
     */
    @Synchronized
    fun shouldRotate180(bitmap: Bitmap, quads: List<DBPostprocessor.Quad>): Boolean {
        val active = session ?: return false
        val name = inputName
        if (name.isEmpty() || quads.isEmpty()) return false
        val candidates = quads.asSequence()

            .map { it.axisAlignedBounds() }
            .map { bounds ->
                val left = bounds[0].coerceIn(0, bitmap.width)
                val top = bounds[1].coerceIn(0, bitmap.height)
                val right = bounds[2].coerceIn(0, bitmap.width)
                val bottom = bounds[3].coerceIn(0, bitmap.height)
                intArrayOf(left, top, right, bottom)
            }
            .filter { bounds ->
                val width = bounds[2] - bounds[0]
                val height = bounds[3] - bounds[1]
                width >= MIN_CROP_SIDE &&
                    height >= MIN_CROP_SIDE &&
                    width >= height * 1.5f
            }
            .distinct()
            .sortedByDescending { bounds ->
                (bounds[2] - bounds[0]).toLong() * (bounds[3] - bounds[1]).toLong()
            }
            .take(MAX_LINES)
            .toList()
        if (candidates.isEmpty()) return false

        var angle180 = 0
        var angle0 = 0
        var best180Confidence = 0f
        for (bounds in candidates) {
            val vote = classifyLine(bitmap, bounds) ?: continue
            if (vote.second < MIN_CONFIDENCE) continue
            if (vote.first == 180) {
                angle180++
                best180Confidence = maxOf(best180Confidence, vote.second)
            } else {
                angle0++
            }
        }
        val confident = angle180 + angle0
        if (confident == 0) return false
        // A page with a single confident 180° line still benefits from a
        // rerun; require a higher confidence because there is no majority.
        val singleLineRotate = confident == 1 &&
            angle180 == 1 &&
            best180Confidence >= SINGLE_LINE_MIN_CONFIDENCE
        return singleLineRotate ||
            (angle180 >= MIN_ANGLE_180_VOTES &&
                angle180.toFloat() / confident.toFloat() >= MIN_ANGLE_180_RATIO)
    }

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

    private fun classifyLine(bitmap: Bitmap, bounds: IntArray): Pair<Int, Float>? {
        val left = bounds[0]
        val top = bounds[1]
        val width = bounds[2] - left
        val height = bounds[3] - top
        if (width < MIN_CROP_SIDE || height < MIN_CROP_SIDE) return null
        val crop = try {
            Bitmap.createBitmap(bitmap, left, top, width, height)
        } catch (_: IllegalArgumentException) {
            return null
        }
        val resized = try {
            Bitmap.createScaledBitmap(crop, INPUT_WIDTH, INPUT_HEIGHT, true)
        } catch (_: IllegalArgumentException) {
            if (!crop.isRecycled) crop.recycle()
            return null
        }
        try {
            val input = rgbNchw(resized)
            val tensor = OnnxTensor.createTensor(
                OcrRuntime.environment,
                directBuffer(input),
                longArrayOf(1, 3, INPUT_HEIGHT.toLong(), INPUT_WIDTH.toLong()),
            )
            tensor.use {
                session?.run(mapOf(inputName to it))?.use { result ->
                    val scores = extractScores(result.get(0).value)
                    if (scores.size != 2) return null
                    val probabilities = probabilities(scores)
                    val best = probabilities.indices.maxByOrNull { index -> probabilities[index] }
                        ?: return null
                    return (if (best == 1) 180 else 0) to probabilities[best]
                }
            }
        } catch (_: OutOfMemoryError) {
            return null
        } catch (_: Throwable) {
            return null
        } finally {
            if (resized !== crop && !resized.isRecycled) resized.recycle()
            if (!crop.isRecycled) crop.recycle()
        }
        return null
    }

    private fun rgbNchw(bitmap: Bitmap): FloatArray {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val plane = width * height
        val output = FloatArray(3 * plane)
        for (index in 0 until plane) {
            val pixel = pixels[index]
            val red = ((pixel ushr 16) and 0xFF) / 255f
            val green = ((pixel ushr 8) and 0xFF) / 255f
            val blue = (pixel and 0xFF) / 255f
            output[index] = (red - MEAN[0]) / STD[0]
            output[plane + index] = (green - MEAN[1]) / STD[1]
            output[2 * plane + index] = (blue - MEAN[2]) / STD[2]
        }
        return output
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
        private const val INPUT_WIDTH = 160
        private const val INPUT_HEIGHT = 80
        private const val MIN_CROP_SIDE = 8
        private const val MAX_LINES = 8
        private const val MIN_CONFIDENCE = 0.85f
        private const val SINGLE_LINE_MIN_CONFIDENCE = 0.99f
        private const val MIN_ANGLE_180_VOTES = 2
        private const val MIN_ANGLE_180_RATIO = 0.6f
        private val MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
        private val STD = floatArrayOf(0.229f, 0.224f, 0.225f)
    }
}
