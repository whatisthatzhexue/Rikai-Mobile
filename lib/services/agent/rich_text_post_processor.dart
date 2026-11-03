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

  Future<RichTextPostProcessResult> process(
    String text, {
    LlmCancelToken? cancellation,
  }) async {
    if (text.isEmpty) {
      return const RichTextPostProcessResult(rejectionReason: 'empty');
    }
    final buffer = StringBuffer();
    try {
      await for (final event in _llm.stream(
        buildRichTextPostProcessRequest(model: _model, text: text),
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
    final normalized = stripRedundantRubyTags(candidate);
    if (stripRichTextTags(stripYomiBlocks(normalized)) !=
        stripYomiBlocks(text)) {
      return const RichTextPostProcessResult(rejectionReason: 'text_changed');
    }
    return RichTextPostProcessResult(taggedText: stripYomiTags(normalized));
  }
}
