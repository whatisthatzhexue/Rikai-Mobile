package com.rikai.ocr

/**
 * Cheap, engine-independent plausibility score for OCR output.
 *
 * PaddleOCR and MangaOCR calibrate their confidence values differently, so
 * choosing a candidate purely by average confidence favours the wrong engine
 * on vertical pages. The score blends confidence with the presence of
 * Japanese kana and meaningful characters, and penalises repetitive garbage
 * such as a decoder emitting one symbol forever.
 */
internal object OcrTextQuality {
    private const val MIN_KANA_RATIO = 0.12
    private const val MIN_UNIQUE_RATIO = 0.12
    private const val REPETITION_PENALTY = 0.25
    private const val SHORT_BLOCK_PENALTY = 0.10

    private val punctuation = (
        "、。，．！？!?「」『』（）()［］｛｝〈〉《》【】〔〕・…‥ー〜～：；:;"
        ).toSet()

    fun score(blocks: List<NativeOcrBlock>): Double {
        if (blocks.isEmpty()) return 0.0
        val text = buildString {
            for (block in blocks) append(block.text)
        }.trim()
        if (text.isEmpty()) return 0.0

        val length = text.length
        val averageConfidence = blocks.map { it.confidence.toDouble() }.average()
        val meaningful = text.count { it.isMeaningful() }
        val kana = text.count { it.isKana() }
        val coverage = meaningful.toDouble() / length
        val kanaScore = (kana.toDouble() / length / MIN_KANA_RATIO).coerceIn(0.0, 1.0)
        val lengthScore = (length / 120.0).coerceIn(0.0, 1.0)
        val uniqueRatio = text.toSet().size.toDouble() / length
        val repetitionPenalty =
            if (length >= 12 && uniqueRatio < MIN_UNIQUE_RATIO) REPETITION_PENALTY else 0.0
        val averageBlockLength = length.toDouble() / blocks.size
        val shortBlockPenalty =
            if (averageBlockLength < 1.5) SHORT_BLOCK_PENALTY else 0.0

        return averageConfidence * 0.45 +
            coverage * 0.25 +
            kanaScore * 0.20 +
            lengthScore * 0.10 -
            repetitionPenalty -
            shortBlockPenalty
    }

    private fun Char.isKana(): Boolean = this in '぀'..'ヿ'

    private fun Char.isMeaningful(): Boolean {
        if (isWhitespace()) return false
        if (this in '\u0000'..'\u001f' || this == '�') return false
        return isLetterOrDigit() || punctuation.contains(this)
    }
}
