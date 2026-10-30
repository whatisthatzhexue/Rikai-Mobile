/// Minimal cancellation signal shared by the run and provider adapters.
///
/// Providers must not poll this on a timer: they register a listener and
/// cancel their HTTP request (for example Dio's `CancelToken`) immediately.
class LlmCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final snapshot = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }
}

enum LlmRole { system, user, assistant }

/// A text-only message part. There is deliberately no image/file variant.
class LlmTextPart {
  const LlmTextPart(this.text);

  final String text;

  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

class LlmMessage {
  const LlmMessage({required this.role, required this.parts});

  final LlmRole role;
  final List<LlmTextPart> parts;

  String get text => parts.map((part) => part.text).join();

  Map<String, Object?> toJson() => {
    'role': role.name,
    'content': parts.map((part) => part.toJson()).toList(),
  };
}

class LlmResponseFormat {
  const LlmResponseFormat({required this.name, required this.schema});

  final String name;
  final Map<String, Object?> schema;
}

class LlmRequest {
  const LlmRequest({
    required this.model,
    required this.messages,
    this.responseFormat,
    this.maxTokens = 16000,
    this.stream = true,
  });

  final String model;
  final List<LlmMessage> messages;
  final LlmResponseFormat? responseFormat;
  final int maxTokens;
  final bool stream;
}

enum LlmEventType { textDelta, reasoningDelta, done, error }

class LlmEvent {
  const LlmEvent({required this.type, this.text = ''});

  final LlmEventType type;
  final String text;

  factory LlmEvent.done() => const LlmEvent(type: LlmEventType.done);
}

abstract interface class LlmPort {
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  });
}
