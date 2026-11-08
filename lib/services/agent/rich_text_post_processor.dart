import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/utils/rich_text_tags.dart';
import 'agent_prompts.dart';
import 'ports/agent_capability_exception.dart';
import 'ports/llm_port.dart';

class RichTextPostProcessResult {
  const RichTextPostProcessResult({this.taggedText, this.rejectionReason = ''});

  final String? taggedText;
  final String rejectionReason;

  bool get accepted => taggedText != null;
}

/// One bounded formatting pass. Any text change or malformed tag is rejected;
/// the caller then renders the original plain text.
///
/// `[YOMI]...[/YOMI]` reading annotations belong to the result-generation
/// model, not to this pass. They are sent to the formatter unchanged. When the
/// formatter fails or leaves a YOMI block in place, the local converter turns
/// that block into an equivalent RUBY pair; if no reading is available, the
/// block is finally converted to the bracket display form (`reading【surface】`).
class RichTextPostProcessor {
  const RichTextPostProcessor({
    required LlmPort llm,
    required String model,
    this.responseLanguage = AgentResponseLanguage.chinese,
    this.onCall,
  }) : _llm = llm,
       _model = model;

  final LlmPort _llm;
  final String _model;

  /// Language of the human-readable explanation. It only shapes prompt wording
  /// (for example "Chinese explanations" vs "English explanations"); the
  /// source text and tags are language-agnostic.
  final AgentResponseLanguage responseLanguage;

  /// Content-free telemetry for the formatting request. The orchestrator uses
  /// it to keep `llmCalls` as the total provider call count.
  final void Function(LlmRequest request, int outputChars, int elapsedMs)?
  onCall;

  static final RegExp _rubyBlockPattern = RegExp(
    r'\[RUBY=[^\]]*\][\s\S]*?\[/RUBY\]',
    caseSensitive: false,
  );

  /// Existing RUBY pairs in the source must survive the formatter. The diff
  /// guard only checks stripped characters, so a model could otherwise drop a
  /// valid source RUBY pair and still be accepted.
  static bool _preservesSourceRuby(String source, String candidate) {
    for (final match in _rubyBlockPattern.allMatches(source)) {
      final block = match.group(0);
      if (block != null && block.isNotEmpty && !candidate.contains(block)) {
        return false;
      }
    }
    return true;
  }

  /// Local-only fallback. The formatter is no longer given pre-converted RUBY,
  /// so the fallback converts the result model's own YOMI annotations directly
  /// to RUBY. It never invents a reading for a word that has no YOMI block.
  static RichTextPostProcessResult _localFallback(
    String source,
    String reason,
  ) {
    final local = localReadingsToRuby(source);
    if (local == source) {
      return RichTextPostProcessResult(rejectionReason: reason);
    }
    final sourcePlain = stripRichTextTags(
      bracketReadingsToRuby(stripYomiBlocks(source)),
    );
    if (!isWellFormedRichText(local) ||
        stripRichTextTags(local) != sourcePlain) {
      return RichTextPostProcessResult(rejectionReason: reason);
    }
    return RichTextPostProcessResult(
      taggedText: local,
      rejectionReason: 'local_yomi_fallback',
    );
  }

  /// Formats several independent sections with a bounded worker pool.
  ///
  /// Identical non-empty texts share one request (for example repeated notes),
  /// and results are returned in the same order as [texts]. Empty entries are
  /// not sent to the provider.
  Future<List<RichTextPostProcessResult>> processAll(
    List<String> texts, {
    LlmCancelToken? cancellation,
    bool detailed = true,
    int concurrency = 2,
  }) async {
    if (texts.isEmpty) return const <RichTextPostProcessResult>[];

    final uniqueTexts = <String>[];
    final uniqueIndexByText = <String, int>{};
    final inputIndexes = <int>[];
    for (final text in texts) {
      if (text.isEmpty) {
        inputIndexes.add(-1);
        continue;
      }
      final index = uniqueIndexByText.putIfAbsent(text, () {
        uniqueTexts.add(text);
        return uniqueTexts.length - 1;
      });
      inputIndexes.add(index);
    }
    if (uniqueTexts.isEmpty) {
      return <RichTextPostProcessResult>[
        for (final _ in texts)
          const RichTextPostProcessResult(rejectionReason: 'empty'),
      ];
    }

    final results = List<RichTextPostProcessResult?>.filled(
      uniqueTexts.length,
      null,
    );
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= uniqueTexts.length) return;
        if (cancellation?.isCancelled == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        results[index] = await process(
          uniqueTexts[index],
          cancellation: cancellation,
          detailed: detailed,
        );
      }
    }

    final workerCount = concurrency.clamp(1, uniqueTexts.length);
    await Future.wait(<Future<void>>[
      for (var index = 0; index < workerCount; index++) worker(),
    ]);

    return <RichTextPostProcessResult>[
      for (final index in inputIndexes)
        index < 0
            ? const RichTextPostProcessResult(rejectionReason: 'empty')
            : results[index]!,
    ];
  }

  Future<RichTextPostProcessResult> process(
    String text, {
    LlmCancelToken? cancellation,
    bool detailed = false,
  }) async {
    if (text.isEmpty) {
      return const RichTextPostProcessResult(rejectionReason: 'empty');
    }
    // Keep the result model's text intact, including YOMI annotations. The
    // formatter is only asked to insert display tags; local YOMI→RUBY is a
    // post-failure/retained-tag fallback, not part of its input.
    // The formatter returns the full text plus tags; a fixed 4000-token cap
    // truncates long originals on providers that honor request.maxTokens.
    final maxTokens = (text.length + 2000).clamp(
      4000,
      AgentLimits.richTextMaxTokens,
    );
    final request = detailed
        ? buildDetailedRubyPostProcessRequest(
            model: _model,
            text: text,
            maxTokens: maxTokens,
            responseLanguage: responseLanguage,
          )
        : buildRichTextPostProcessRequest(
            model: _model,
            text: text,
            maxTokens: maxTokens,
          );
    final buffer = StringBuffer();
    try {
      await for (final event in _llm.stream(
        request,
        cancellation: cancellation,
      )) {
        if (cancellation?.isCancelled == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        switch (event.type) {
          case LlmEventType.textDelta:
            buffer.write(event.text);
          case LlmEventType.error:
            return _localFallback(text, 'provider_error');
          case LlmEventType.reasoningDelta:
          case LlmEventType.done:
            break;
        }
      }
    } on AgentCapabilityException catch (error) {
      if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
      return _localFallback(text, error.message);
    } catch (_) {
      return _localFallback(text, 'provider_error');
    }

    return _acceptCandidate(text, buffer.toString());
  }

  /// Formats the original section and every sentence-level interpretation in
  /// one request. Dictionary notes are intentionally excluded: their readings
  /// are rendered locally from `word[YOMI]reading[/YOMI]` / `reading【surface】`,
  /// so they never need a provider call.
  ///
  /// The response is split by the section markers and each section still goes
  /// through the same character diff as [process]. One bad section falls back
  /// locally without discarding the other sections.
  Future<List<RichTextPostProcessResult>> processSections(
    List<String> sectionIds,
    List<String> sectionTexts, {
    LlmCancelToken? cancellation,
    int maxChars = AgentLimits.defaultMaxRichTextChars,
  }) async {
    assert(sectionIds.length == sectionTexts.length);
    if (sectionTexts.isEmpty) return const <RichTextPostProcessResult>[];
    final totalChars = sectionTexts.fold<int>(
      0,
      (sum, text) => sum + text.length,
    );
    if (totalChars > maxChars) {
      return _fallbackAll(sectionTexts, 'batch_too_long');
    }
    final maxTokens = (totalChars + 2000).clamp(
      4000,
      AgentLimits.richTextMaxTokens,
    );
    final request = buildBatchedRichTextPostProcessRequest(
      model: _model,
      sectionIds: sectionIds,
      sectionTexts: sectionTexts,
      maxTokens: maxTokens,
      responseLanguage: responseLanguage,
    );
    final buffer = StringBuffer();
    final watch = Stopwatch()..start();
    try {
      try {
        await for (final event in _llm.stream(
          request,
          cancellation: cancellation,
        )) {
          if (cancellation?.isCancelled == true) {
            throw const AgentCapabilityException(
              AgentToolErrorCode.toolCancelled,
              '已取消',
            );
          }
          switch (event.type) {
            case LlmEventType.textDelta:
              buffer.write(event.text);
            case LlmEventType.error:
              return _fallbackAll(sectionTexts, 'provider_error');
            case LlmEventType.reasoningDelta:
            case LlmEventType.done:
              break;
          }
        }
      } finally {
        onCall?.call(request, buffer.length, watch.elapsedMilliseconds);
      }
    } on AgentCapabilityException catch (error) {
      if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
      return _fallbackAll(sectionTexts, error.message);
    } catch (_) {
      return _fallbackAll(sectionTexts, 'provider_error');
    }

    final sections = _splitSections(buffer.toString(), sectionIds);
    return <RichTextPostProcessResult>[
      for (var index = 0; index < sectionTexts.length; index++)
        sections[index] == null
            ? _localFallback(sectionTexts[index], 'batch_marker')
            : _acceptCandidate(sectionTexts[index], sections[index]!),
    ];
  }

  List<RichTextPostProcessResult> _fallbackAll(
    List<String> texts,
    String reason,
  ) {
    return <RichTextPostProcessResult>[
      for (final text in texts) _localFallback(text, reason),
    ];
  }

  /// Splits a batched response by section id. A missing or damaged marker
  /// yields null for that section only; later sections are still searched and
  /// can be accepted. This is required by R-AGENT-LIMITS-001/T-137: one bad
  /// section must never force a whole-batch local fallback.
  List<String?> _splitSections(String raw, List<String> ids) {
    final sections = <String?>[];
    var cursor = 0;
    for (final id in ids) {
      final openMarker = richTextSectionOpen(id);
      final closeMarker = richTextSectionClose(id);
      final openIndex = raw.indexOf(openMarker, cursor);
      if (openIndex < 0) {
        sections.add(null);
        continue;
      }
      final bodyStart = openIndex + openMarker.length;
      final closeIndex = raw.indexOf(closeMarker, bodyStart);
      if (closeIndex < 0) {
        sections.add(null);
        // Continue after the open marker so later sections can still be
        // recovered instead of losing the whole batch.
        cursor = bodyStart;
        continue;
      }
      // The prompt builder puts one newline after the open marker and one
      // before the close marker. Section sources are already trimmed, so
      // trimming the captured body is the stable normalization.
      sections.add(raw.substring(bodyStart, closeIndex).trim());
      cursor = closeIndex + closeMarker.length;
    }
    return sections;
  }

  RichTextPostProcessResult _acceptCandidate(String text, String candidate) {
    if (candidate.isEmpty) {
      return _localFallback(text, 'empty_output');
    }
    if (!isWellFormedYomi(candidate)) {
      return _localFallback(text, 'malformed_yomi');
    }
    if (!allowsYomiDeletion(text, candidate)) {
      return _localFallback(text, 'yomi_changed');
    }
    var normalized = cleanRubyReadings(candidate);
    normalized = stripRedundantRubyTags(normalized);
    var tagsRepaired = false;
    if (!isWellFormedRichText(normalized)) {
      // A formatter can emit valid content with one orphan/mis-nested
      // BOLD/UNDERLINE tag. Drop only the broken style tags and keep the rest
      // instead of discarding every emphasis in the section. Malformed RUBY or
      // YOMI still falls back to the local reading baseline.
      final repaired = _repairSimpleStyleTags(normalized);
      if (!isWellFormedRichText(repaired)) {
        return _localFallback(text, 'malformed_tags');
      }
      normalized = repaired;
      tagsRepaired = true;
    }
    // The analysis model may already have emitted display tags despite the
    // prompt (for example [RUBY=...]). They are formatting, not source text,
    // so both sides must be compared with their display tags removed.
    // Bracket readings are display annotations too: `reading【surface】` and
    // `[RUBY=reading]surface[/RUBY]` describe the same base text. Parentheses
    // are ordinary explanations and are deliberately not normalized.
    final sourcePlain = stripRichTextTags(
      bracketReadingsToRuby(stripYomiBlocks(text)),
    );
    final candidatePlain = stripRichTextTags(
      bracketReadingsToRuby(stripYomiBlocks(normalized)),
    );
    if (candidatePlain != sourcePlain) {
      return _localFallback(text, 'text_changed');
    }
    if (!_preservesSourceRuby(text, normalized)) {
      return _localFallback(text, 'source_ruby_dropped');
    }
    // If the formatter left YOMI blocks or bracket readings in place, convert
    // them locally. This avoids a plain `reading【surface】` result when the
    // model chose not to add RUBY. The converter is tag-aware, so a reading
    // outside a just-closed BOLD/UNDERLINE is moved back inside the emphasis
    // span as RUBY (and a duplicate after RUBY is dropped).
    final local = localReadingsToRuby(normalized);
    if (local != normalized &&
        isWellFormedRichText(local) &&
        stripRichTextTags(local) == sourcePlain) {
      return RichTextPostProcessResult(
        taggedText: local,
        rejectionReason: tagsRepaired ? 'tags_repaired' : '',
      );
    }
    return RichTextPostProcessResult(
      taggedText: stripYomiTags(normalized),
      rejectionReason: tagsRepaired ? 'tags_repaired' : '',
    );
  }

  /// Drops orphan, duplicate or mis-nested BOLD/UNDERLINE tags while leaving
  /// RUBY pairs and every base character untouched. It is deliberately
  /// conservative: malformed RUBY/YOMI is not repaired here.
  static String _repairSimpleStyleTags(String text) {
    final matches = richTextTagPattern.allMatches(text).toList(growable: false);
    if (matches.isEmpty) return text;
    final output = <String>[];
    final stack = <({String tag, int index})>[];
    final skippedClosings = <String, int>{};
    var cursor = 0;
    var rubyDepth = 0;

    for (final match in matches) {
      output.add(text.substring(cursor, match.start));
      cursor = match.end;
      final tag = (match.group(1) ?? '').toLowerCase();
      if (tag.startsWith('ruby=')) {
        rubyDepth++;
        output.add(match.group(0) ?? '');
        continue;
      }
      if (tag == '/ruby') {
        if (rubyDepth > 0) rubyDepth--;
        output.add(match.group(0) ?? '');
        continue;
      }
      // Style tags inside a RUBY base are invalid; drop them rather than
      // invalidating the whole section.
      if (rubyDepth > 0) continue;
      if (tag == 'bold' || tag == 'underline') {
        if (stack.any((entry) => entry.tag == tag)) {
          skippedClosings[tag] = (skippedClosings[tag] ?? 0) + 1;
          continue;
        }
        final index = output.length;
        output.add(match.group(0) ?? '');
        stack.add((tag: tag, index: index));
        continue;
      }
      final closing = tag.startsWith('/') ? tag.substring(1) : tag;
      final skipped = skippedClosings[closing] ?? 0;
      if (skipped > 0) {
        skippedClosings[closing] = skipped - 1;
        continue;
      }
      if (stack.isNotEmpty && stack.last.tag == closing) {
        stack.removeLast();
        output.add(match.group(0) ?? '');
      }
      // Orphan or mis-nested closing tags are dropped.
    }
    output.add(text.substring(cursor));
    for (final entry in stack) {
      output[entry.index] = '';
    }
    return output.join();
  }
}
