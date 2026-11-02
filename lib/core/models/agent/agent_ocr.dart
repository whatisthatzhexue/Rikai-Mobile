import 'agent_input.dart';

/// Deterministic quality signals for one on-device OCR variant.
///
/// These values are computed locally and never sent to the provider. They are
/// used to decide whether the user should be offered an explicit multi-OCR
/// comparison and to rank variants; the model does not choose OCR output.
class OcrQuality {
  const OcrQuality({
    required this.charCount,
    required this.meaningfulChars,
    required this.duplicateNoiseRatio,
    this.meanConfidence = 0,
    this.dictionaryHitRate,
    this.contentWords = 0,
  });

  /// Conservative thresholds. They are deliberately local constants so tests
  /// and UI copy do not drift from the decision logic.
  static const double lowConfidenceThreshold = 0.75;
  static const double lowDictionaryHitRate = 0.35;
  static const double highDuplicateNoiseRatio = 0.15;
  static const int minMeaningfulChars = 2;
  static const int minContentWordsForHitRate = 3;

  /// UTF-16 length (same unit as token/quote offsets).
  final int charCount;

  /// Letters, digits, kana, CJK ideographs and other scripts; punctuation and
  /// whitespace are excluded. No script-specific ratio is used for quality or
  /// ranking, so the same logic also works for non-Japanese MDict dictionaries.
  final int meaningfulChars;

  /// Share of characters that belong to runs of the same meaningful character
  /// three or more times long. Repeating OCR garbage is a useful local signal.
  final double duplicateNoiseRatio;
  final double meanConfidence;

  /// Share of content-word targets with at least one dictionary citation.
  /// Null when tokenization or dictionary probing was unavailable.
  final double? dictionaryHitRate;
  final int contentWords;

  double get meaningfulRatio =>
      charCount == 0 ? 0 : meaningfulChars / charCount;

  bool get hasDictionarySignal =>
      dictionaryHitRate != null && contentWords >= minContentWordsForHitRate;

  bool get isLowQuality {
    if (meaningfulChars < minMeaningfulChars) return true;
    if (meanConfidence > 0 && meanConfidence < lowConfidenceThreshold) {
      return true;
    }
    if (duplicateNoiseRatio >= highDuplicateNoiseRatio) return true;
    if (hasDictionarySignal && dictionaryHitRate! < lowDictionaryHitRate) {
      return true;
    }
    return false;
  }

  /// Ranking score in [0, 1]. When dictionary evidence exists it dominates;
  /// otherwise confidence plus script/noise signals are used.
  double get rankScore {
    final confidence = meanConfidence > 0 ? meanConfidence : 0.5;
    final noise = 1 - duplicateNoiseRatio.clamp(0.0, 1.0);
    final script = meaningfulRatio.clamp(0.0, 1.0);
    if (hasDictionarySignal) {
      return (0.35 * confidence +
              0.40 * dictionaryHitRate! +
              0.15 * script +
              0.10 * noise)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return (0.60 * confidence + 0.25 * script + 0.15 * noise)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

/// One contiguous span of a text used in an OCR variant diff.
class OcrDiffSpan {
  const OcrDiffSpan({
    required this.text,
    required this.start,
    required this.end,
    required this.changed,
  });

  final String text;

  /// UTF-16 offsets in the text this span belongs to.
  final int start;
  final int end;
  final bool changed;
}

/// Character-level comparison between the selected OCR text (base) and a
/// candidate variant. Both sides use UTF-16 offsets.
class OcrTextDiff {
  const OcrTextDiff({
    required this.baseSpans,
    required this.candidateSpans,
    required this.baseChangedChars,
    required this.candidateChangedChars,
  });

  final List<OcrDiffSpan> baseSpans;
  final List<OcrDiffSpan> candidateSpans;
  final int baseChangedChars;
  final int candidateChangedChars;

  bool get identical => baseChangedChars == 0 && candidateChangedChars == 0;

  List<OcrDiffSpan> get changedBaseSpans =>
      baseSpans.where((span) => span.changed).toList(growable: false);

  List<OcrDiffSpan> get changedCandidateSpans =>
      candidateSpans.where((span) => span.changed).toList(growable: false);
}

/// One variant plus its quality and diff against the baseline variant.
class OcrVariantComparison {
  const OcrVariantComparison({
    required this.variant,
    required this.quality,
    required this.diffFromBaseline,
    required this.recommended,
  });

  final AgentOcrVariant variant;
  final OcrQuality quality;

  /// Always relative to the baseline variant, not to the user's current
  /// preview selection, so the UI can switch chips without recomputing.
  final OcrTextDiff diffFromBaseline;
  final bool recommended;
}

/// A display-ready variant set: baseline, comparisons and recommendation.
class OcrVariantSetView {
  const OcrVariantSetView({
    required this.baselineVariantId,
    required this.comparisons,
    required this.recommendedVariantId,
  });

  final String baselineVariantId;
  final List<OcrVariantComparison> comparisons;
  final String recommendedVariantId;
}

/// One dictionary-backed replacement candidate for a suspicious OCR span.
class OcrRepairCandidate {
  const OcrRepairCandidate({
    required this.text,
    this.dictionaryIds = const <String>[],
    this.score = 0,
  });

  final String text;
  final List<String> dictionaryIds;
  final double score;
}

/// A suspicious span in the baseline OCR text and its local dictionary
/// suggestions. Suggestions are never applied automatically.
class OcrRepairSuggestion {
  const OcrRepairSuggestion({
    required this.original,
    required this.start,
    required this.end,
    required this.candidates,
  });

  final String original;

  /// UTF-16 offsets in the baseline text.
  final int start;
  final int end;
  final List<OcrRepairCandidate> candidates;
}
