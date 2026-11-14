/*
 * Adapted from Screen Translator (overlay-translator), Copyright 2026 ciddwd.
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified for Rikai-Mobile: extracted the PaddleOCR YAML character-dict
 * parser and CTC greedy decoder into a standalone class.
 */
package com.rikai.ocr

import java.io.File

internal class CtcDictionary private constructor(val keys: List<String>) {
    val classCount: Int get() = keys.size + 2

    data class Decoded(
        val text: String,
        val score: Float,
        val steps: Int,
        val nonBlankSteps: Int,
    )

    fun decode(logits: Array<FloatArray>): Decoded {
        if (logits.isEmpty()) return Decoded("", 0f, 0, 0)
        val text = StringBuilder()
        var previous = -1
        var nonBlank = 0
        var scoreTotal = 0f
        var emitted = 0
        for (step in logits) {
            if (step.isEmpty()) continue
            var best = 0
            var bestValue = step[0]
            for (index in 1 until step.size) {
                if (step[index] > bestValue) {
                    best = index
                    bestValue = step[index]
                }
            }
            if (best != 0 && best != previous) {
                nonBlank++
                val keyIndex = best - 1
                when {
                    keyIndex in keys.indices -> {
                        text.append(keys[keyIndex])
                        scoreTotal += bestValue
                        emitted++
                    }
                    keyIndex == keys.size -> {
                        text.append(' ')
                        scoreTotal += bestValue
                        emitted++
                    }
                }
            }
            previous = best
        }
        return Decoded(
            text = text.toString().trim(),
            score = if (emitted == 0) 0f else (scoreTotal / emitted).coerceIn(0f, 1f),
            steps = logits.size,
            nonBlankSteps = nonBlank,
        )
    }

    companion object {
        fun load(file: File): CtcDictionary {
            if (!file.isFile || file.length() == 0L) {
                throw OcrFailure("MODEL_INVALID", "OCR 字符表不存在：${file.name}")
            }
            val lines = file.readText(Charsets.UTF_8)
                .removePrefix("﻿")
                .split('\n')
                .map { it.trimEnd('\r') }

            val keys = mutableListOf<String>()
            var inDictionary = false
            for (line in lines) {
                if (line.trim() == "character_dict:") {
                    inDictionary = true
                    continue
                }
                if (!inDictionary) continue
                val trimmed = line.trimStart()
                if (!trimmed.startsWith("- ")) {
                    if (line.isNotBlank() && !line.trimStart().startsWith("#")) break
                    continue
                }
                // Keep U+3000 and other YAML scalar characters intact. Do not
                // call trim() on the value: PP-OCR's first key is an ideographic
                // space and trim() would erase it.
                val raw = trimmed.substring(2)
                keys.add(parseYamlScalar(raw))
            }
            if (keys.isEmpty()) {
                // Plain newline dictionary fallback.
                lines.map { it.trimEnd('\r') }
                    .filter { it.isNotEmpty() }
                    .forEach { keys.add(it) }
            }
            if (keys.isEmpty()) {
                throw OcrFailure("MODEL_INVALID", "OCR 字符表为空：${file.name}")
            }
            return CtcDictionary(keys.toList())
        }

        private fun parseYamlScalar(raw: String): String {
            if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
                return raw.substring(1, raw.length - 1).replace("''", "'")
            }
            if (raw.length >= 2 && raw.startsWith("\"") && raw.endsWith("\"")) {
                return unescapeYamlDoubleQuoted(raw.substring(1, raw.length - 1))
            }
            return raw.trimEnd(' ')
        }

        /** YAML 1.1 scalar escapes used by PyYAML output. */
        private fun unescapeYamlDoubleQuoted(body: String): String {
            val out = StringBuilder(body.length)
            var i = 0
            while (i < body.length) {
                val c = body[i]
                if (c != '\\' || i + 1 >= body.length) {
                    out.append(c)
                    i++
                    continue
                }
                val escape = body[i + 1]
                val hexLength = when (escape) {
                    'x' -> 2
                    'u' -> 4
                    'U' -> 8
                    else -> 0
                }
                if (hexLength > 0) {
                    val codePoint = body.substring(i + 2, minOf(body.length, i + 2 + hexLength))
                        .takeIf { it.length == hexLength }
                        ?.toIntOrNull(16)
                    if (codePoint != null && Character.isValidCodePoint(codePoint)) {
                        out.appendCodePoint(codePoint)
                        i += 2 + hexLength
                    } else {
                        out.append(c)
                        i++
                    }
                    continue
                }
                val replacement = when (escape) {
                    '0' -> "\u0000"
                    'a' -> "\u0007"
                    'b' -> "\b"
                    't', '\t' -> "\t"
                    'n' -> "\n"
                    'v' -> "\u000B"
                    'f' -> "\u000C"
                    'r' -> "\r"
                    'e' -> "\u001B"
                    ' ' -> " "
                    '"' -> "\""
                    '/' -> "/"
                    '\\' -> "\\"
                    'N' -> "\u0085"
                    '_' -> " "
                    'L' -> " "
                    'P' -> " "
                    else -> null
                }
                if (replacement != null) {
                    out.append(replacement)
                    i += 2
                } else {
                    out.append(c)
                    i++
                }
            }
            return out.toString()
        }
    }
}

internal class OcrFailure(val code: String, override val message: String) : Exception(message)
