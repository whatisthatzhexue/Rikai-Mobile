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
/// model, not to this pass. A whole YOMI block may be deleted only when the
/// formatter replaces its reading with RUBY; retained blocks are returned with
/// their tags stripped, so the UI shows the parenthetical reading.
class RichTextPostProcessor {
  const RichTextPostProcessor({required LlmPort llm, required String model})
    : _llm = llm,
      _model = model;

  final LlmPort _llm;
  final String _model;

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
            return const RichTextPostProcessResult(
              rejectionReason: 'provider_error',
            );
          case LlmEventType.reasoningDelta:
          case LlmEventType.done:
            break;
        }
      }
    } on AgentCapabilityException catch (error) {
      if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
      return RichTextPostProcessResult(rejectionReason: error.message);
    } catch (_) {
      return const RichTextPostProcessResult(rejectionReason: 'provider_error');
    }

    final candidate = buffer.toString();
    if (candidate.isEmpty) {
      return const RichTextPostProcessResult(rejectionReason: 'empty_output');
    }
    if (!isWellFormedYomi(candidate)) {
      return const RichTextPostProcessResult(rejectionReason: 'malformed_yomi');
    }
    if (!allowsYomiDeletion(text, candidate)) {
      return const RichTextPostProcessResult(rejectionReason: 'yomi_changed');
    }
    if (!isWellFormedRichText(candidate)) {
      return const RichTextPostProcessResult(rejectionReason: 'malformed_tags');
    }
    var normalized = cleanRubyReadings(candidate);
    normalized = stripRedundantRubyTags(normalized);
    // The analysis model may already have emitted display tags despite the
    // prompt (for example [RUBY=...]). They are formatting, not source text,
    // so both sides must be compared with their display tags removed.
    final sourcePlain = stripRichTextTags(stripYomiBlocks(text));
    if (stripRichTextTags(stripYomiBlocks(normalized)) != sourcePlain) {
      return const RichTextPostProcessResult(rejectionReason: 'text_changed');
    }
    return RichTextPostProcessResult(taggedText: stripYomiTags(normalized));
  }
}
