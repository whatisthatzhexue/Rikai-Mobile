/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: package name, removed overlay/mask support and
 * the optional column-splitting path. The DBNet post-processing algorithm is
 * kept: probability map -> connected components -> convex hull -> minimum
 * area rectangle -> score check -> unclip.
 */
package com.rikai.ocr

import android.graphics.PointF
import kotlin.math.hypot
import kotlin.math.sqrt

internal object DBPostprocessor {
    /**
     * Rotated rectangle corners ordered left-top, right-top, right-bottom,
     * left-bottom. p0 -> p1 is the text baseline direction.
     */
    data class Quad(val p0: PointF, val p1: PointF, val p2: PointF, val p3: PointF) {
        val centerX: Float get() = (p0.x + p1.x + p2.x + p3.x) / 4f
        val centerY: Float get() = (p0.y + p1.y + p2.y + p3.y) / 4f
        val width: Float get() = hypot(p1.x - p0.x, p1.y - p0.y)
        val height: Float get() = hypot(p3.x - p0.x, p3.y - p0.y)

        fun axisAlignedBounds(): IntArray {
            val xs = floatArrayOf(p0.x, p1.x, p2.x, p3.x)
            val ys = floatArrayOf(p0.y, p1.y, p2.y, p3.y)
            return intArrayOf(xs.min().toInt(), ys.min().toInt(), xs.max().toInt(), ys.max().toInt())
        }

        fun cornerPoints(): FloatArray =
            floatArrayOf(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y)
    }

    private data class IntPoint(val x: Int, val y: Int)

    /**
     * Extract quads from a DBNet probability map and map them back to the
     * source image using [scaleX]/[scaleY].
     */
    fun extractQuads(
        probMap: Array<FloatArray>,
        scaleX: Float,
        scaleY: Float,
        binThresh: Float = 0.3f,
        scoreThresh: Float = 0.6f,
        unclipRatio: Float = 1.6f,
        minSide: Int = 3,
    ): List<Quad> {
        if (probMap.isEmpty()) return emptyList()
        val height = probMap.size
        val width = probMap[0].size
        if (height == 0 || width == 0) return emptyList()

        val visited = Array(height) { BooleanArray(width) }
        val result = mutableListOf<Quad>()
        for (y0 in 0 until height) {
            for (x0 in 0 until width) {
                if (visited[y0][x0] || probMap[y0][x0] < binThresh) continue
                val component = mutableListOf<IntPoint>()
                val boundary = mutableListOf<IntPoint>()
                val stack = ArrayDeque<IntArray>()
                stack.addLast(intArrayOf(x0, y0))
                visited[y0][x0] = true
                while (stack.isNotEmpty()) {
                    val cell = stack.removeLast()
                    val cx = cell[0]
                    val cy = cell[1]
                    component.add(IntPoint(cx, cy))
                    var isBoundary = false
                    for (neighbor in NEIGHBORS_8) {
                        val nx = cx + neighbor[0]
                        val ny = cy + neighbor[1]
                        if (nx !in 0 until width || ny !in 0 until height) {
                            isBoundary = true
                            continue
                        }
                        if (probMap[ny][nx] < binThresh) {
                            isBoundary = true
                            continue
                        }
                        if (!visited[ny][nx]) {
                            visited[ny][nx] = true
                            stack.addLast(intArrayOf(nx, ny))
                        }
                    }
                    if (isBoundary) boundary.add(IntPoint(cx, cy))
                }
                if (component.size < 16) continue
                val hull = convexHull(if (boundary.isNotEmpty()) boundary else component)
                if (hull.size < 3) continue
                val quad = minAreaRect(hull) ?: continue
                if (minOf(quad.width, quad.height) < minSide) continue
                if (boxScore(probMap, quad) < scoreThresh) continue
                val expanded = unclip(quad, unclipRatio)
                result.add(
                    Quad(
                        point(expanded.p0.x * scaleX, expanded.p0.y * scaleY),
                        point(expanded.p1.x * scaleX, expanded.p1.y * scaleY),
                        point(expanded.p2.x * scaleX, expanded.p2.y * scaleY),
                        point(expanded.p3.x * scaleX, expanded.p3.y * scaleY),
                    ),
                )
            }
        }
        return result
    }

    /**
     * PaddleX recognition-crop geometry: round and clamp every corner, then
     * refit a minimum-area rectangle and order it LT, RT, RB, LB.
     */
    fun fitRecognitionCropQuad(quad: Quad, imageWidth: Int, imageHeight: Int): Quad? {
        val corners = listOf(quad.p0, quad.p1, quad.p2, quad.p3).map { point ->
            IntPoint(
                Math.round(point.x).coerceIn(0, imageWidth),
                Math.round(point.y).coerceIn(0, imageHeight),
            )
        }
        return minAreaRect(convexHull(corners))
    }

    internal fun unclip(quad: Quad, ratio: Float): Quad {
        val width = quad.width
        val height = quad.height
        if (width <= 1f || height <= 1f) return quad
        val distance = width * height * ratio / (2 * (width + height))
        val ux = (quad.p1.x - quad.p0.x) / width
        val uy = (quad.p1.y - quad.p0.y) / width
        val vx = (quad.p3.x - quad.p0.x) / height
        val vy = (quad.p3.y - quad.p0.y) / height
        fun shift(point: PointF, du: Float, dv: Float) =
            point(point.x + du * ux + dv * vx, point.y + du * uy + dv * vy)
        return Quad(
            shift(quad.p0, -distance, -distance),
            shift(quad.p1, distance, -distance),
            shift(quad.p2, distance, distance),
            shift(quad.p3, -distance, distance),
        )
    }

    private fun convexHull(points: List<IntPoint>): List<IntPoint> {
        if (points.size <= 2) return points
        val sorted = points.distinct().sortedWith(compareBy({ it.x }, { it.y }))
        if (sorted.size <= 2) return sorted
        val hull = mutableListOf<IntPoint>()
        for (point in sorted) {
            while (hull.size >= 2 && cross(hull[hull.size - 2], hull[hull.size - 1], point) <= 0) {
                hull.removeAt(hull.size - 1)
            }
            hull.add(point)
        }
        val lower = hull.size + 1
        for (index in sorted.size - 2 downTo 0) {
            val point = sorted[index]
            while (hull.size >= lower && cross(hull[hull.size - 2], hull[hull.size - 1], point) <= 0) {
                hull.removeAt(hull.size - 1)
            }
            hull.add(point)
        }
        hull.removeAt(hull.size - 1)
        return hull
    }

    private fun cross(origin: IntPoint, a: IntPoint, b: IntPoint): Long =
        (a.x - origin.x).toLong() * (b.y - origin.y) -
            (a.y - origin.y).toLong() * (b.x - origin.x)

    private fun minAreaRect(hull: List<IntPoint>): Quad? {
        if (hull.size < 3) return null
        var bestArea = Double.MAX_VALUE
        var bestQuad: Quad? = null
        for (index in hull.indices) {
            val a = hull[index]
            val b = hull[(index + 1) % hull.size]
            val dx = (b.x - a.x).toDouble()
            val dy = (b.y - a.y).toDouble()
            val length = sqrt(dx * dx + dy * dy)
            if (length < 1e-6) continue
            val ux = dx / length
            val uy = dy / length
            val vx = -uy
            val vy = ux
            var minU = Double.MAX_VALUE
            var maxU = -Double.MAX_VALUE
            var minV = Double.MAX_VALUE
            var maxV = -Double.MAX_VALUE
            for (point in hull) {
                val u = point.x * ux + point.y * uy
                val v = point.x * vx + point.y * vy
                if (u < minU) minU = u
                if (u > maxU) maxU = u
                if (v < minV) minV = v
                if (v > maxV) maxV = v
            }
            val width = maxU - minU
            val height = maxV - minV
            val area = width * height
            if (area < bestArea && width > 1 && height > 1) {
                bestArea = area
                fun toPoint(u: Double, v: Double) =
                    point((u * ux + v * vx).toFloat(), (u * uy + v * vy).toFloat())
                bestQuad = sortCorners(
                    toPoint(minU, minV),
                    toPoint(maxU, minV),
                    toPoint(maxU, maxV),
                    toPoint(minU, maxV),
                )
            }
        }
        return bestQuad
    }

    private fun sortCorners(a: PointF, b: PointF, c: PointF, d: PointF): Quad {
        val sorted = listOf(a, b, c, d).sortedBy { it.x }
        val left = sorted.take(2).sortedBy { it.y }
        val right = sorted.drop(2).sortedBy { it.y }
        return Quad(left[0], right[0], right[1], left[1])
    }

    private fun boxScore(probMap: Array<FloatArray>, quad: Quad): Float {
        val bounds = quad.axisAlignedBounds()
        val height = probMap.size
        val width = probMap[0].size
        val x0 = bounds[0].coerceAtLeast(0)
        val y0 = bounds[1].coerceAtLeast(0)
        val x1 = bounds[2].coerceAtMost(width - 1)
        val y1 = bounds[3].coerceAtMost(height - 1)
        if (x1 <= x0 || y1 <= y0) return 0f
        var sum = 0.0
        var count = 0
        val polygon = listOf(quad.p0, quad.p1, quad.p2, quad.p3)
        for (y in y0..y1) {
            for (x in x0..x1) {
                if (pointInQuad(x + 0.5f, y + 0.5f, polygon)) {
                    sum += probMap[y][x]
                    count++
                }
            }
        }
        return if (count == 0) 0f else (sum / count).toFloat()
    }

    private fun pointInQuad(x: Float, y: Float, polygon: List<PointF>): Boolean {
        var inside = false
        var j = polygon.size - 1
        for (i in polygon.indices) {
            val xi = polygon[i].x
            val yi = polygon[i].y
            val xj = polygon[j].x
            val yj = polygon[j].y
            if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi + 1e-9f) + xi) {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    private fun point(x: Float, y: Float): PointF = PointF().apply {
        this.x = x
        this.y = y
    }

    private val NEIGHBORS_8 = arrayOf(
        intArrayOf(-1, -1), intArrayOf(0, -1), intArrayOf(1, -1),
        intArrayOf(-1, 0), intArrayOf(1, 0),
        intArrayOf(-1, 1), intArrayOf(0, 1), intArrayOf(1, 1),
    )

}
