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
/// block is finally stripped to a plain parenthetical.
class RichTextPostProcessor {
  const RichTextPostProcessor({required LlmPort llm, required String model})
    : _llm = llm,
      _model = model;

  final LlmPort _llm;
  final String _model;

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
      parentheticalReadingsToRuby(stripYomiBlocks(source)),
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
    final maxTokens = (text.length + 2000).clamp(4000, 16000);
    final request = detailed
        ? buildDetailedRubyPostProcessRequest(
            model: _model,
            text: text,
            maxTokens: maxTokens,
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

    final candidate = buffer.toString();
    if (candidate.isEmpty) {
      return _localFallback(text, 'empty_output');
    }
    if (!isWellFormedYomi(candidate)) {
      return _localFallback(text, 'malformed_yomi');
    }
    if (!allowsYomiDeletion(text, candidate)) {
      return _localFallback(text, 'yomi_changed');
    }
    if (!isWellFormedRichText(candidate)) {
      return _localFallback(text, 'malformed_tags');
    }
    var normalized = cleanRubyReadings(candidate);
    normalized = stripRedundantRubyTags(normalized);
    // The analysis model may already have emitted display tags despite the
    // prompt (for example [RUBY=...]). They are formatting, not source text,
    // so both sides must be compared with their display tags removed.
    // Parenthetical readings are display annotations too: `word（reading）`
    // and `[RUBY=reading]word[/RUBY]` describe the same base text.
    final sourcePlain = stripRichTextTags(
      parentheticalReadingsToRuby(stripYomiBlocks(text)),
    );
    final candidatePlain = stripRichTextTags(
      parentheticalReadingsToRuby(stripYomiBlocks(normalized)),
    );
    if (candidatePlain != sourcePlain) {
      return _localFallback(text, 'text_changed');
    }
    if (!_preservesSourceRuby(text, normalized)) {
      return _localFallback(text, 'source_ruby_dropped');
    }
    // If the formatter left YOMI blocks or parenthetical readings in place,
    // convert them locally. This avoids a plain `word（reading）` result when
    // the model chose not to add RUBY. The converter is tag-aware, so a
    // reading outside a just-closed BOLD/UNDERLINE is moved back inside the
    // emphasis span as RUBY (and a duplicate after RUBY is dropped).
    final local = localReadingsToRuby(normalized);
    if (local != normalized &&
        isWellFormedRichText(local) &&
        stripRichTextTags(local) == sourcePlain) {
      return RichTextPostProcessResult(taggedText: local);
    }
    return RichTextPostProcessResult(taggedText: stripYomiTags(normalized));
  }
}
