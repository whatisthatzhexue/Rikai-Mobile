import 'agent_json.dart';

/// Where a source version came from.
enum AgentQuoteOrigin {
  ocr('ocr'),
  userText('user_text'),
  userEdit('user_edit'),
  dictionaryRepair('dictionary_repair');

  const AgentQuoteOrigin(this.wireName);

  final String wireName;

  static AgentQuoteOrigin fromWire(Object? value) {
    for (final item in AgentQuoteOrigin.values) {
      if (item.wireName == value) return item;
    }
    return AgentQuoteOrigin.ocr;
  }
}

/// A source text version. Offsets are UTF-16, matching `Token.start/end`.
class AgentSourceVersion {
  const AgentSourceVersion({
    required this.id,
    required this.sourceId,
    required this.origin,
    required this.text,
    this.imageId,
    this.variantId,
    this.blocksJson = '[]',
    this.engine = '',
    this.mode = '',
    this.confidence = 0,
  });

  final String id;
  final String sourceId;
  final AgentQuoteOrigin origin;
  final String text;
  final String? imageId;
  final String? variantId;
  final String blocksJson;
  final String engine;
  final String mode;
  final double confidence;

  Map<String, Object?> toJson() => {
    'id': id,
    'source_id': sourceId,
    if (imageId != null) 'image_id': imageId,
    if (variantId != null) 'variant_id': variantId,
    'origin': origin.wireName,
    'text': text,
    'blocks_json': blocksJson,
    if (engine.isNotEmpty) 'engine': engine,
    if (mode.isNotEmpty) 'mode': mode,
    'confidence': confidence,
  };

  factory AgentSourceVersion.fromJson(Map<String, Object?> json) {
    return AgentSourceVersion(
      id: agentString(json['id']),
      sourceId: agentString(json['source_id']),
      imageId: json['image_id'] is String ? json['image_id'] as String : null,
      variantId: json['variant_id'] is String
          ? json['variant_id'] as String
          : null,
      origin: AgentQuoteOrigin.fromWire(json['origin']),
      text: agentString(json['text']),
      blocksJson: agentString(json['blocks_json'], '[]'),
      engine: agentString(json['engine']),
      mode: agentString(json['mode']),
      confidence: agentDouble(json['confidence']),
    );
  }
}

/// A validated span of the selected source text. Quotes are not citations.
class AgentQuoteRef {
  const AgentQuoteRef({
    required this.id,
    required this.sourceId,
    required this.start,
    required this.end,
    required this.text,
    required this.origin,
  });

  static const String schema = 'rikai.agent.quote.v1';

  final String id;
  final String sourceId;
  final int start;
  final int end;
  final String text;
  final AgentQuoteOrigin origin;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'id': id,
    'source_id': sourceId,
    'start': start,
    'end': end,
    'text': text,
    'origin': origin.wireName,
  };

  factory AgentQuoteRef.fromJson(Map<String, Object?> json) {
    return AgentQuoteRef(
      id: agentString(json['id']),
      sourceId: agentString(json['source_id']),
      start: agentInt(json['start']),
      end: agentInt(json['end']),
      text: agentString(json['text']),
      origin: AgentQuoteOrigin.fromWire(json['origin']),
    );
  }
}
