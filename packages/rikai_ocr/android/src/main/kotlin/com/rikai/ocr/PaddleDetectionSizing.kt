/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: fixed Phase 3 detection profile (max side 960).
 */
package com.rikai.ocr

import kotlin.math.roundToInt

internal data class PaddleDetectionResizePlan(
    val sourceWidth: Int,
    val sourceHeight: Int,
    val targetWidth: Int,
    val targetHeight: Int,
) {
    val resized: Boolean
        get() = sourceWidth != targetWidth || sourceHeight != targetHeight
}

internal object PaddleDetectionSizing {
    private const val ALIGNMENT = 32
    const val MAX_SIDE = 960

    fun plan(sourceWidth: Int, sourceHeight: Int): PaddleDetectionResizePlan {
        val safeWidth = sourceWidth.coerceAtLeast(1)
        val safeHeight = sourceHeight.coerceAtLeast(1)
        val longest = maxOf(safeWidth, safeHeight)
        val ratio = minOf(1f, MAX_SIDE.toFloat() / longest)
        return PaddleDetectionResizePlan(
            sourceWidth = safeWidth,
            sourceHeight = safeHeight,
            targetWidth = align((safeWidth * ratio).roundToInt()),
            targetHeight = align((safeHeight * ratio).roundToInt()),
        )
    }

    private fun align(value: Int): Int {
        val rounded = ((value + ALIGNMENT / 2) / ALIGNMENT) * ALIGNMENT
        return rounded.coerceIn(ALIGNMENT, MAX_SIDE)
    }
}
