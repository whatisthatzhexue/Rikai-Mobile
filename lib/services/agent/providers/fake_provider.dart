import '../ports/llm_port.dart';

/// Canned provider used by unit/widget tests and the fake-server harness.
class FakeProvider implements LlmPort {
  FakeProvider({
    this.responseText = '{}',
    this.responseSequence,
    this.events,
  });

  final String responseText;

  /// Optional per-request responses, used by the repair-call tests. The last
  /// entry is reused once the sequence is exhausted.
  final List<String>? responseSequence;
  final List<LlmEvent>? events;
  final List<LlmRequest> requests = <LlmRequest>[];

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    requests.add(request);
    final canned = events;
    if (canned != null) {
      for (final event in canned) {
        yield event;
      }
      return;
    }
    final sequence = responseSequence;
    final text = sequence == null || sequence.isEmpty
        ? responseText
        : sequence[(requests.length - 1).clamp(0, sequence.length - 1)];
    if (text.isNotEmpty) {
      yield LlmEvent(type: LlmEventType.textDelta, text: text);
    }
    yield LlmEvent.done();
  }
}
