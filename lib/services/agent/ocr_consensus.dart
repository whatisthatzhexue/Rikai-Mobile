import 'dart:math' as math;

import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_ocr.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/models/dict_info.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/lookup_request.dart';
import '../../core/models/token.dart';
import '../../core/utils/html_text.dart';
import 'ports/agent_capability_exception.dart';
import 'ports/lookup_port.dart';
import 'ports/tokenize_port.dart';

/// Local dictionary probe result shared by OCR quality scoring and the
/// pre-commit variant preview. It never creates a formal citation.
class OcrDictionaryProbe {
  const OcrDictionaryProbe({
    required this.rate,
    required this.words,
    required this.preview,
  });

  final double rate;
  final int words;
  final OcrVariantLookupPreview preview;
}

/// Local, deterministic OCR comparison and dictionary-assisted repair.
///
/// Nothing here calls a provider. Images never leave the device; only the
/// resulting text/variants participate in a later analysis run.
abstract final class OcrConsensus {
  static const int maxDiffChars = 6000;
  static const int maxDiffMiddleForLcs = 256;
  static const int maxRepairSuggestions = 6;
  static const int maxRepairQueries = 16;
  static const int maxRepairChunkChars = 6;
  static const int maxHitRateWords = 12;

  /// Assess a variant using the text itself and an optional locally measured
  /// dictionary hit signal.
  static OcrQuality assess({
    required AgentOcrVariant variant,
    double? dictionaryHitRate,
    int contentWords = 0,
  }) {
    final text = variant.text;
    var meaningful = 0;
    for (final rune in text.runes) {
      if (_isMeaningfulRune(rune)) meaningful++;
    }
    return OcrQuality(
      charCount: text.length,
      meaningfulChars: meaningful,
      duplicateNoiseRatio: _duplicateNoiseRatio(text),
      meanConfidence: variant.confidence,
      dictionaryHitRate: dictionaryHitRate,
      contentWords: contentWords,
    );
  }

  /// Assess the selected variant with the actual token evidence used for the
  /// run (content tokens that received at least one citation).
  static OcrQuality assessWithEvidence({
    required AgentOcrVariant variant,
    required AgentSourceEvidence evidence,
  }) {
    var contentWords = 0;
    var matched = 0;
    for (final token in evidence.tokens) {
      if (!token.content) continue;
      contentWords++;
      if (token.citationIds.isNotEmpty) matched++;
    }
    return assess(
      variant: variant,
      dictionaryHitRate: contentWords == 0 ? null : matched / contentWords,
      contentWords: contentWords,
    );
  }

  /// Compare variants against [baseline]. The baseline itself is always
  /// included, `recommendedVariantId` is deterministic, and a tie keeps the
  /// baseline (the user's current result must not silently lose to a tie).
  static OcrVariantSetView compare({
    required AgentOcrVariant baseline,
    required List<AgentOcrVariant> variants,
    Map<String, OcrQuality> qualityById = const <String, OcrQuality>{},
  }) {
    final byId = <String, AgentOcrVariant>{baseline.id: baseline};
    for (final variant in variants) {
      byId.putIfAbsent(variant.id, () => variant);
    }
    final baselineScore =
        (qualityById[baseline.id] ?? assess(variant: baseline)).rankScore;
    var recommendedId = baseline.id;
    var bestScore = baselineScore;
    for (final variant in byId.values) {
      if (variant.id == baseline.id) continue;
      final score =
          (qualityById[variant.id] ?? assess(variant: variant)).rankScore;
      if (score > bestScore) {
        bestScore = score;
        recommendedId = variant.id;
      }
    }
    final comparisons = <OcrVariantComparison>[
      for (final variant in byId.values)
        OcrVariantComparison(
          variant: variant,
          quality: qualityById[variant.id] ?? assess(variant: variant),
          diffFromBaseline: diff(baseline.text, variant.text),
          recommended: variant.id == recommendedId,
        ),
    ];
    return OcrVariantSetView(
      baselineVariantId: baseline.id,
      comparisons: comparisons,
      recommendedVariantId: recommendedId,
    );
  }

  /// Character-level diff with bounded work. Common prefix/suffix are always
  /// recognized; a small changed middle uses LCS, a large one is marked as a
  /// single changed span instead of spending unbounded CPU.
  static OcrTextDiff diff(
    String base,
    String candidate, {
    int maxChars = maxDiffChars,
  }) {
    final baseLimit = math.min(base.length, maxChars);
    final candidateLimit = math.min(candidate.length, maxChars);
    final a = base.substring(0, baseLimit);
    final b = candidate.substring(0, candidateLimit);
    final baseSpans = <OcrDiffSpan>[];
    final candidateSpans = <OcrDiffSpan>[];
    if (a.isEmpty && b.isEmpty) {
      return const OcrTextDiff(
        baseSpans: <OcrDiffSpan>[],
        candidateSpans: <OcrDiffSpan>[],
        baseChangedChars: 0,
        candidateChangedChars: 0,
      );
    }

    var prefix = 0;
    final minLength = math.min(a.length, b.length);
    while (prefix < minLength && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLength - prefix &&
        a.codeUnitAt(a.length - 1 - suffix) ==
            b.codeUnitAt(b.length - 1 - suffix)) {
      suffix++;
    }

    if (prefix > 0) {
      _addSpan(baseSpans, a.substring(0, prefix), 0, prefix, false);
      _addSpan(candidateSpans, b.substring(0, prefix), 0, prefix, false);
    }

    final baseMiddleStart = prefix;
    final baseMiddleEnd = a.length - suffix;
    final candidateMiddleStart = prefix;
    final candidateMiddleEnd = b.length - suffix;
    final baseMiddle = a.substring(baseMiddleStart, baseMiddleEnd);
    final candidateMiddle = b.substring(
      candidateMiddleStart,
      candidateMiddleEnd,
    );
    if (baseMiddle.isNotEmpty || candidateMiddle.isNotEmpty) {
      if (baseMiddle.length <= maxDiffMiddleForLcs &&
          candidateMiddle.length <= maxDiffMiddleForLcs) {
        final middle = _lcsSpans(
          baseMiddle,
          candidateMiddle,
          baseMiddleStart,
          candidateMiddleStart,
        );
        baseSpans.addAll(middle.$1);
        candidateSpans.addAll(middle.$2);
      } else {
        _addSpan(baseSpans, baseMiddle, baseMiddleStart, baseMiddleEnd, true);
        _addSpan(
          candidateSpans,
          candidateMiddle,
          candidateMiddleStart,
          candidateMiddleEnd,
          true,
        );
      }
    }

    if (suffix > 0) {
      _addSpan(
        baseSpans,
        a.substring(a.length - suffix),
        a.length - suffix,
        a.length,
        false,
      );
      _addSpan(
        candidateSpans,
        b.substring(b.length - suffix),
        b.length - suffix,
        b.length,
        false,
      );
    }

    // Text beyond maxChars is deliberately not diffed. Keep it visible as an
    // unchanged tail in both sides so offsets remain meaningful.
    if (base.length > baseLimit) {
      _addSpan(
        baseSpans,
        base.substring(baseLimit),
        baseLimit,
        base.length,
        false,
      );
    }
    if (candidate.length > candidateLimit) {
      _addSpan(
        candidateSpans,
        candidate.substring(candidateLimit),
        candidateLimit,
        candidate.length,
        false,
      );
    }

    return OcrTextDiff(
      baseSpans: baseSpans,
      candidateSpans: candidateSpans,
      baseChangedChars: _changedChars(baseSpans),
      candidateChangedChars: _changedChars(candidateSpans),
    );
  }

  /// Measure how many unique content words are found in the selected
  /// dictionaries. This is a bounded probe (at most [maxWords]) used only for
  /// OCR quality/ranking, never for answer evidence.
  static Future<({double rate, int words})?> measureDictionaryHits({
    required String text,
    required TokenizePort tokenizePort,
    required LookupPort lookupPort,
    required List<DictionaryInfo> dictionaries,
    int maxWords = maxHitRateWords,
    bool Function()? isCancelled,
  }) async {
    final probe = await probeDictionary(
      text: text,
      tokenizePort: tokenizePort,
      lookupPort: lookupPort,
      dictionaries: dictionaries,
      maxWords: maxWords,
      isCancelled: isCancelled,
    );
    return probe == null ? null : (rate: probe.rate, words: probe.words);
  }

  /// Measures the same bounded hit rate as [measureDictionaryHits] and also
  /// collects up to [maxPreviewEntries] cleaned snippets for the pre-commit
  /// variant comparison. No provider or CitationRegistry is involved.
  static Future<OcrDictionaryProbe?> probeDictionary({
    required String text,
    required TokenizePort tokenizePort,
    required LookupPort lookupPort,
    required List<DictionaryInfo> dictionaries,
    int maxWords = maxHitRateWords,
    int maxPreviewEntries = 3,
    int maxSnippetChars = 240,
    bool Function()? isCancelled,
  }) async {
    if (dictionaries.isEmpty || text.trim().isEmpty) return null;
    List<Token> tokens;
    try {
      tokens = await tokenizePort.analyze(text);
    } catch (_) {
      return null;
    }
    final candidates = <String>[];
    for (final token in tokens) {
      if (!token.isContentWord) continue;
      final candidate = _firstUsableCandidate(token);
      if (candidate == null) continue;
      if (!candidates.contains(candidate)) candidates.add(candidate);
      if (candidates.length >= maxWords) break;
    }
    if (candidates.length < OcrQuality.minContentWordsForHitRate) return null;
    var hits = 0;
    var failed = 0;
    final entries = <OcrLookupPreviewEntry>[];
    final seenEntries = <String>{};
    for (final candidate in candidates) {
      if (isCancelled?.call() == true) return null;
      try {
        final result = await lookupPort.lookup(
          LookupRequest(
            query: candidate,
            dictionaries: dictionaries,
            matchMode: LookupMatchMode.exact,
            maxEntriesPerDictionary: 1,
          ),
        );
        if (result.groups.isNotEmpty &&
            result.groups.every((group) => group.error.isNotEmpty)) {
          failed++;
          continue;
        }
        if (result.hasHits) {
          hits++;
          if (entries.length < maxPreviewEntries) {
            for (final group in result.groups) {
              if (group.entries.isEmpty) continue;
              final entry = group.entries.first;
              final headword = entry.headword.isEmpty
                  ? entry.matchedKey
                  : entry.headword;
              final key =
                  '${group.dictionary.id}\u0000$headword\u0000${entry.matchedKey}';
              if (!seenEntries.add(key)) continue;
              final snippet = cleanDictionaryText(
                htmlToPlainText(entry.html),
                maxLength: maxSnippetChars,
              );
              if (snippet.isEmpty) continue;
              entries.add(
                OcrLookupPreviewEntry(
                  dictionaryId: group.dictionary.id,
                  dictionaryTitle: group.dictionary.title,
                  headword: headword,
                  snippet: snippet,
                ),
              );
              if (entries.length >= maxPreviewEntries) break;
            }
          }
        }
      } on AgentCapabilityException catch (error) {
        if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
        failed++;
      } catch (_) {
        // A single dictionary failure must not invalidate the quality probe.
        failed++;
      }
    }
    final attempted = candidates.length - failed;
    if (attempted == 0) return null;
    return OcrDictionaryProbe(
      rate: hits / attempted,
      words: attempted,
      preview: OcrVariantLookupPreview(
        hitCount: hits,
        entries: List<OcrLookupPreviewEntry>.unmodifiable(entries),
      ),
    );
  }

  /// Suggest dictionary-backed replacements for suspicious spans in [text].
  /// Only exact-match misses are considered, suggestions must be close in
  /// length and share the first character, and the lookup count is bounded.
  /// Suggestions are advisory; nothing is applied here.
  static Future<List<OcrRepairSuggestion>> suggestRepairs({
    required String text,
    required OcrTextDiff diff,
    required List<DictionaryInfo> dictionaries,
    required LookupPort lookupPort,
    int maxSuggestions = maxRepairSuggestions,
    int maxQueries = maxRepairQueries,
    bool Function()? isCancelled,
  }) async {
    if (dictionaries.isEmpty || text.isEmpty) {
      return const <OcrRepairSuggestion>[];
    }
    final suggestions = <OcrRepairSuggestion>[];
    var queries = 0;
    for (final span in diff.changedBaseSpans) {
      if (suggestions.length >= maxSuggestions || queries >= maxQueries) {
        break;
      }
      if (span.end > text.length || span.start < 0) continue;
      final spanText = text.substring(span.start, span.end);
      var cursor = 0;
      for (final chunkInfo in _repairChunks(spanText)) {
        if (suggestions.length >= maxSuggestions || queries >= maxQueries) {
          break;
        }
        final chunk = chunkInfo.text;
        final local = span.start + chunkInfo.start;
        if (local < cursor || chunk.length < 2) continue;
        cursor = local + chunk.length;
        queries++;
        LookupResult exact;
        try {
          exact = await lookupPort.lookup(
            LookupRequest(
              query: chunk,
              dictionaries: dictionaries,
              matchMode: LookupMatchMode.exact,
              maxEntriesPerDictionary: 1,
            ),
          );
        } on AgentCapabilityException catch (error) {
          if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
          continue;
        } catch (_) {
          continue;
        }
        // If the span is already a real dictionary word, it is not a repair.
        if (exact.hasHits) continue;
        if (queries >= maxQueries) break;
        queries++;
        List<String> rawSuggestions;
        try {
          rawSuggestions = await lookupPort.suggest(
            prefix: chunk.substring(0, 1),
            dictionaries: dictionaries,
            limit: 5,
          );
        } on AgentCapabilityException catch (error) {
          if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
          continue;
        } catch (_) {
          continue;
        }
        final candidates = <OcrRepairCandidate>[];
        for (final candidate in rawSuggestions) {
          final trimmed = candidate.trim();
          if (trimmed.isEmpty || trimmed == chunk) continue;
          if ((trimmed.length - chunk.length).abs() > 2) continue;
          if (_firstRune(trimmed) != _firstRune(chunk)) continue;
          candidates.add(
            OcrRepairCandidate(
              text: trimmed,
              score: _candidateScore(chunk, trimmed),
            ),
          );
          if (candidates.length >= 2) break;
        }
        if (candidates.isEmpty) continue;
        candidates.sort((left, right) => right.score.compareTo(left.score));
        suggestions.add(
          OcrRepairSuggestion(
            original: chunk,
            start: local,
            end: local + chunk.length,
            candidates: candidates,
          ),
        );
      }
    }
    return suggestions;
  }

  /// Build a new variant with one dictionary candidate applied. The original
  /// OCR variant is never mutated; the returned variant records
  /// [AgentQuoteOrigin.dictionaryRepair].
  static AgentOcrVariant? applyRepair({
    required AgentOcrVariant baseline,
    required OcrRepairSuggestion suggestion,
    required OcrRepairCandidate candidate,
    required String id,
  }) {
    return applyRepairs(
      baseline: baseline,
      selections: <OcrRepairSelection>[
        OcrRepairSelection(suggestion: suggestion, candidate: candidate),
      ],
      id: id,
    );
  }

  /// Applies at most one candidate per suspicious span. Selections are applied
  /// from the end of the text backwards so earlier UTF-16 offsets stay valid
  /// when replacements change the text length. Overlapping or out-of-range
  /// selections are ignored; the original variant is never mutated.
  static AgentOcrVariant? applyRepairs({
    required AgentOcrVariant baseline,
    required List<OcrRepairSelection> selections,
    required String id,
  }) {
    if (selections.isEmpty) return null;
    final ordered = <OcrRepairSelection>[...selections]
      ..sort(
        (left, right) =>
            right.suggestion.start.compareTo(left.suggestion.start),
      );
    var text = baseline.text;
    var previousStart = text.length;
    var changed = false;
    for (final selection in ordered) {
      final suggestion = selection.suggestion;
      if (suggestion.start < 0 ||
          suggestion.end < suggestion.start ||
          suggestion.end > text.length ||
          suggestion.end > previousStart) {
        continue;
      }
      final replaced = text.replaceRange(
        suggestion.start,
        suggestion.end,
        selection.candidate.text,
      );
      if (replaced == text) continue;
      text = replaced;
      previousStart = suggestion.start;
      changed = true;
    }
    if (!changed) return null;
    return AgentOcrVariant(
      id: id,
      engine: 'dictionary_repair',
      mode: baseline.mode,
      text: text,
      confidence: baseline.confidence,
      elapsedMs: 0,
      origin: AgentQuoteOrigin.dictionaryRepair,
    );
  }

  static (List<OcrDiffSpan>, List<OcrDiffSpan>) _lcsSpans(
    String a,
    String b,
    int aStart,
    int bStart,
  ) {
    final n = a.length;
    final m = b.length;
    final table = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = a.codeUnitAt(i) == b.codeUnitAt(j)
            ? table[i + 1][j + 1] + 1
            : math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
    final aSpans = <OcrDiffSpan>[];
    final bSpans = <OcrDiffSpan>[];
    var i = 0;
    var j = 0;
    var aRunStart = 0;
    var bRunStart = 0;
    bool? runChanged;

    void flush(int aEnd, int bEnd) {
      final changed = runChanged;
      if (changed == null) return;
      if (aEnd > aRunStart) {
        _addSpan(
          aSpans,
          a.substring(aRunStart, aEnd),
          aStart + aRunStart,
          aStart + aEnd,
          changed,
        );
      }
      if (bEnd > bRunStart) {
        _addSpan(
          bSpans,
          b.substring(bRunStart, bEnd),
          bStart + bRunStart,
          bStart + bEnd,
          changed,
        );
      }
    }

    while (i < n || j < m) {
      final same = i < n && j < m && a.codeUnitAt(i) == b.codeUnitAt(j);
      final changed = !same;
      if (runChanged == null) {
        runChanged = changed;
        aRunStart = i;
        bRunStart = j;
      } else if (runChanged != changed) {
        flush(i, j);
        runChanged = changed;
        aRunStart = i;
        bRunStart = j;
      }
      if (same) {
        i++;
        j++;
      } else if (j >= m || (i < n && table[i + 1][j] >= table[i][j + 1])) {
        i++;
      } else {
        j++;
      }
    }
    flush(n, m);
    return (aSpans, bSpans);
  }

  static void _addSpan(
    List<OcrDiffSpan> spans,
    String text,
    int start,
    int end,
    bool changed,
  ) {
    if (text.isEmpty) return;
    if (spans.isNotEmpty && spans.last.changed == changed) {
      final previous = spans.removeLast();
      spans.add(
        OcrDiffSpan(
          text: previous.text + text,
          start: previous.start,
          end: end,
          changed: changed,
        ),
      );
      return;
    }
    spans.add(
      OcrDiffSpan(text: text, start: start, end: end, changed: changed),
    );
  }

  static int _changedChars(List<OcrDiffSpan> spans) {
    var count = 0;
    for (final span in spans) {
      if (span.changed) count += span.end - span.start;
    }
    return count;
  }

  static double _duplicateNoiseRatio(String text) {
    if (text.isEmpty) return 0;
    var noise = 0;
    var run = 1;
    var previous = text.codeUnitAt(0);
    for (var index = 1; index < text.length; index++) {
      final current = text.codeUnitAt(index);
      if (current == previous && _isMeaningfulRune(current)) {
        run++;
      } else {
        if (run >= 3) noise += run - 2;
        run = 1;
        previous = current;
      }
    }
    if (run >= 3) noise += run - 2;
    return noise / text.length;
  }

  static double _candidateScore(String original, String candidate) {
    var prefix = 0;
    final limit = math.min(original.length, candidate.length);
    while (prefix < limit &&
        original.codeUnitAt(prefix) == candidate.codeUnitAt(prefix)) {
      prefix++;
    }
    final lengthScore = prefix / math.max(original.length, candidate.length);
    final sameLength = original.length == candidate.length ? 0.2 : 0.0;
    return (lengthScore + sameLength).clamp(0.0, 1.0).toDouble();
  }

  /// Split a changed span into script-neutral 2–6 character chunks. Runs are
  /// bounded by punctuation/whitespace, so no kana/Latin assumption is made.
  static List<({String text, int start})> _repairChunks(String text) {
    final chunks = <({String text, int start})>[];
    final buffer = StringBuffer();
    var runStart = -1;
    var offset = 0;

    void flush() {
      if (buffer.isEmpty) return;
      var value = buffer.toString();
      if (value.length > maxRepairChunkChars) {
        value = value.substring(0, maxRepairChunkChars);
      }
      if (value.length >= 2) {
        chunks.add((text: value, start: runStart));
      }
      buffer.clear();
      runStart = -1;
    }

    for (final rune in text.runes) {
      final length = rune > 0xffff ? 2 : 1;
      if (_isMeaningfulRune(rune)) {
        if (runStart < 0) runStart = offset;
        buffer.writeCharCode(rune);
      } else {
        flush();
      }
      offset += length;
    }
    flush();
    return chunks;
  }

  static String? _firstUsableCandidate(Token token) {
    for (final raw in token.lookupCandidates) {
      final value = raw.trim();
      if (value.isEmpty || value == '*' || value == '-' || value == '－') {
        continue;
      }
      return value;
    }
    final surface = token.surface.trim();
    return surface.isEmpty ? null : surface;
  }

  static int? _firstRune(String text) => text.isEmpty ? null : text.runes.first;

  /// Script-neutral meaningful-character test. It does not classify kana,
  /// kanji, Latin or any other language specifically, so OCR quality works for
  /// other-language dictionaries too. Whitespace, control and common
  /// punctuation/symbol ranges are excluded.
  static bool _isMeaningfulRune(int rune) {
    if (rune <= 0x20) return false;
    if (rune >= 0x7f && rune <= 0xa0) return false;
    if (rune >= 0xa1 && rune <= 0xbf) return false;
    if (rune == 0xd7 || rune == 0xf7) return false;
    if (rune >= 0x2000 && rune <= 0x206f) return false;
    if (rune >= 0x3000 && rune <= 0x303f) return false;
    if (rune == 0x30a0 || rune == 0x30fb) return false;
    if (rune >= 0xff01 && rune <= 0xff0f) return false;
    if (rune >= 0xff1a && rune <= 0xff20) return false;
    if (rune >= 0xff3b && rune <= 0xff40) return false;
    if (rune >= 0xff5b && rune <= 0xff65) return false;
    if (rune >= 0x1f000 && rune <= 0x1faff) return false;
    return true;
  }
}
