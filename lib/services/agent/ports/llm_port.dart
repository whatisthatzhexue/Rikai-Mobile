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

class LlmRequest {
  const LlmRequest({
    required this.model,
    required this.messages,
    this.maxTokens = 16000,
    this.stream = true,
    this.maxHttpAttempts = 3,
    this.onHttpAttempt,
  });

  final String model;
  final List<LlmMessage> messages;
  final int maxTokens;
  final bool stream;

  /// Total HTTP attempts allowed by the provider adapter, including the first
  /// one. Normal Agent runs keep the historical 3-attempt retry; a connectivity
  /// test sets this to 1 so it never retries automatically.
  final int maxHttpAttempts;

  /// Called by provider adapters for every HTTP attempt, including retries.
  /// Used only for content-free telemetry; it must never receive prompt text.
  final void Function(int attempt, bool retry)? onHttpAttempt;

  LlmRequest copyWith({
    List<LlmMessage>? messages,
    int? maxTokens,
    bool? stream,
    int? maxHttpAttempts,
    void Function(int attempt, bool retry)? onHttpAttempt,
  }) {
    return LlmRequest(
      model: model,
      messages: messages ?? this.messages,
      maxTokens: maxTokens ?? this.maxTokens,
      stream: stream ?? this.stream,
      maxHttpAttempts: maxHttpAttempts ?? this.maxHttpAttempts,
      onHttpAttempt: onHttpAttempt ?? this.onHttpAttempt,
    );
  }
}

enum LlmEventType { textDelta, reasoningDelta, done, error }

class LlmEvent {
  const LlmEvent({required this.type, this.text = ''});

  final LlmEventType type;
  final String text;

  factory LlmEvent.done() => const LlmEvent(type: LlmEventType.done);
}

abstract interface class LlmPort {
  Stream<LlmEvent> stream(LlmRequest request, {LlmCancelToken? cancellation});
}
