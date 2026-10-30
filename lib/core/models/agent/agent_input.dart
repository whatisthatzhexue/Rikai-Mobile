import 'package:rikai_ocr/rikai_ocr.dart' show OcrMode;

import 'agent_json.dart';

/// Strict/loose answer policy for one Agent request.
enum AgentMode {
  strict,
  loose;

  String get wireName => name;

  static AgentMode fromWire(Object? value) {
    return value == 'loose' ? AgentMode.loose : AgentMode.strict;
  }
}

/// How a source entered the request.
enum AgentSourceKind {
  imageOcr('image_ocr'),
  userText('user_text');

  const AgentSourceKind(this.wireName);

  final String wireName;

  static AgentSourceKind fromWire(Object? value) {
    return value == AgentSourceKind.userText.wireName
        ? AgentSourceKind.userText
        : AgentSourceKind.imageOcr;
  }
}

/// One dictionary visible to this Agent session, in the user's order.
class AgentDictionaryRef {
  const AgentDictionaryRef({
    required this.id,
    required this.title,
    required this.order,
  });

  final String id;
  final String title;
  final int order;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'order': order};

  factory AgentDictionaryRef.fromJson(Map<String, Object?> json) {
    return AgentDictionaryRef(
      id: agentString(json['id']),
      title: agentString(json['title']),
      order: agentInt(json['order']),
    );
  }
}

/// One on-device OCR result. [text] is normalized/composed, never a path.
class AgentOcrVariant {
  const AgentOcrVariant({
    required this.id,
    required this.engine,
    required this.mode,
    required this.text,
    this.confidence = 0,
    this.elapsedMs = 0,
  });

  final String id;
  final String engine;
  final OcrMode mode;
  final String text;
  final double confidence;
  final int elapsedMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'engine': engine,
    'mode': mode.name,
    'text': text,
    'confidence': confidence,
    'elapsed_ms': elapsedMs,
  };

  factory AgentOcrVariant.fromJson(Map<String, Object?> json) {
    final modeName = agentString(json['mode'], OcrMode.auto.name);
    return AgentOcrVariant(
      id: agentString(json['id']),
      engine: agentString(json['engine'], 'unknown'),
      mode: OcrMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => OcrMode.auto,
      ),
      text: agentString(json['text']),
      confidence: agentDouble(json['confidence']),
      elapsedMs: agentInt(json['elapsed_ms']),
    );
  }
}

/// An image OCR source or a plain-text source.
class AgentSourceInput {
  const AgentSourceInput({
    required this.id,
    required this.kind,
    this.text = '',
    this.imageId,
    this.selectedVariantId,
    this.variants = const <AgentOcrVariant>[],
  });

  final String id;
  final AgentSourceKind kind;
  final String text;

  /// Opaque image handle. Never a path or file name.
  final String? imageId;
  final String? selectedVariantId;
  final List<AgentOcrVariant> variants;

  bool get isImage => kind == AgentSourceKind.imageOcr;

  AgentOcrVariant? get selectedVariant {
    for (final variant in variants) {
      if (variant.id == selectedVariantId) return variant;
    }
    return variants.isEmpty ? null : variants.first;
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'id': id,
      'kind': kind.wireName,
      if (text.isNotEmpty) 'text': text,
      if (imageId != null) 'image_id': imageId,
      if (selectedVariantId != null) 'selected_variant_id': selectedVariantId,
      if (variants.isNotEmpty)
        'variants': variants.map((variant) => variant.toJson()).toList(),
    };
    return json;
  }

  factory AgentSourceInput.fromJson(Map<String, Object?> json) {
    final kind = AgentSourceKind.fromWire(json['kind']);
    final rawVariants = json['variants'];
    return AgentSourceInput(
      id: agentString(json['id']),
      kind: kind,
      text: agentString(json['text']),
      imageId: json['image_id'] is String ? json['image_id'] as String : null,
      selectedVariantId: json['selected_variant_id'] is String
          ? json['selected_variant_id'] as String
          : null,
      variants: rawVariants is List
          ? rawVariants
                .whereType<Map>()
                .map(
                  (value) => AgentOcrVariant.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentOcrVariant>[],
    );
  }
}

/// The only input sent to the provider for one Agent run.
///
/// It contains text, token/dictionary evidence and source handles only. Never
/// include image bytes, image paths, file URIs or provider vision fields.
class AgentInputEnvelope {
  const AgentInputEnvelope({
    required this.sessionId,
    required this.mode,
    required this.sources,
    this.userText = '',
    this.context = '',
    this.dictionaries = const <AgentDictionaryRef>[],
  });

  static const String schema = 'rikai.agent.input.v1';

  final String sessionId;
  final AgentMode mode;
  final List<AgentSourceInput> sources;
  final String userText;
  final String context;
  final List<AgentDictionaryRef> dictionaries;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'session_id': sessionId,
    'mode': mode.wireName,
    if (userText.isNotEmpty) 'user_text': userText,
    if (context.isNotEmpty) 'context': context,
    'dictionaries': dictionaries
        .map((dictionary) => dictionary.toJson())
        .toList(),
    'sources': sources.map((source) => source.toJson()).toList(),
  };

  factory AgentInputEnvelope.fromJson(Map<String, Object?> json) {
    final rawDictionaries = json['dictionaries'];
    final rawSources = json['sources'];
    return AgentInputEnvelope(
      sessionId: agentString(json['session_id']),
      mode: AgentMode.fromWire(json['mode']),
      userText: agentString(json['user_text']),
      context: agentString(json['context']),
      dictionaries: rawDictionaries is List
          ? rawDictionaries
                .whereType<Map>()
                .map(
                  (value) => AgentDictionaryRef.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentDictionaryRef>[],
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (value) => AgentSourceInput.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentSourceInput>[],
    );
  }
}
