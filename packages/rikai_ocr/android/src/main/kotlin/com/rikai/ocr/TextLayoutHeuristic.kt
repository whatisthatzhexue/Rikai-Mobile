/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: reduced to the geometry-only text-layout hint used
 * to route a page between the PaddleOCR horizontal recognizer and MangaOCR.
 */
package com.rikai.ocr

/**
 * Decides whether a set of DBNet text boxes is more likely to be vertical
 * Japanese text (tategaki) than horizontal text.
 *
 * This intentionally mirrors the conservative part of the upstream heuristic:
 * a small number of boxes falls back to horizontal so a title or a UI label
 * never silently switches engines. Three strongly vertical boxes are enough to
 * override a few horizontal boxes (status bars, page headers, etc.).
 */
internal object TextLayoutHeuristic {
    private const val PORTRAIT_RATIO = 2.0f
    private const val STRONG_VERTICAL_RATIO = 5.0f
    private const val STRONG_VERTICAL_MIN_COUNT = 3

    fun isStrongHorizontal(quad: DBPostprocessor.Quad): Boolean {
        val width = quad.width.coerceAtLeast(1f)
        val height = quad.height.coerceAtLeast(1f)
        return width > height * PORTRAIT_RATIO
    }

    fun isStrongVertical(quad: DBPostprocessor.Quad): Boolean {
        val width = quad.width.coerceAtLeast(1f)
        val height = quad.height.coerceAtLeast(1f)
        return height > width * PORTRAIT_RATIO
    }

    fun isVertical(quads: List<DBPostprocessor.Quad>): Boolean {
        if (quads.isEmpty()) return false
        if (quads.size == 1) {
            val bounds = quads.first().axisAlignedBounds()
            val width = (bounds[2] - bounds[0]).coerceAtLeast(1)
            val height = (bounds[3] - bounds[1]).coerceAtLeast(1)
            return height > width * PORTRAIT_RATIO
        }

        var portrait = 0
        var landscape = 0
        var strongVertical = 0
        for (quad in quads) {
            val bounds = quad.axisAlignedBounds()
            val width = (bounds[2] - bounds[0]).coerceAtLeast(1)
            val height = (bounds[3] - bounds[1]).coerceAtLeast(1)
            when {
                height > width * STRONG_VERTICAL_RATIO -> {
                    strongVertical++
                    portrait++
                }
                height > width * PORTRAIT_RATIO -> portrait++
                width > height * PORTRAIT_RATIO -> landscape++
            }
        }
        if (strongVertical >= STRONG_VERTICAL_MIN_COUNT) return true
        // A single tall tategaki column can be split by DBNet into one box per
        // glyph. Those boxes are square, but their centres form a vertical
        // stack. Treat that as vertical unless the boxes also spread
        // horizontally like a normal horizontal line.
        if (looksStacked(quads)) return true
        val total = quads.size
        return portrait > landscape && portrait.toFloat() / total >= 0.5f
    }

    private fun looksStacked(quads: List<DBPostprocessor.Quad>): Boolean {
        if (quads.size < 3) return false
        val boxes = quads.map { it.axisAlignedBounds() }
        // Consider only square/tall boxes. This lets a vertical column coexist
        // with a horizontal caption on a mixed page without the caption
        // disqualifying the whole stack.
        val candidates = boxes.filter { bounds ->
            val width = (bounds[2] - bounds[0]).coerceAtLeast(1)
            val height = (bounds[3] - bounds[1]).coerceAtLeast(1)
            width.toFloat() / height <= 1.6f
        }
        if (candidates.size < 3) return false
        val averageWidth = candidates.map { (it[2] - it[0]).coerceAtLeast(1) }
            .average().toFloat()
        val centers = candidates.map { (it[0] + it[2]) / 2f }
        val spreadX = (centers.maxOrNull() ?: 0f) - (centers.minOrNull() ?: 0f)
        if (spreadX > averageWidth * 0.5f) return false
        val sorted = candidates.sortedBy { it[1] }
        val totalHeight = (sorted.last()[3] - sorted.first()[1]).coerceAtLeast(1)
        val averageHeight = candidates.map { (it[3] - it[1]).coerceAtLeast(1) }
            .average().toFloat()
        return totalHeight / averageHeight >= 2.5f
    }
}
