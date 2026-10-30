import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/agent_orchestrator.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/citation_registry.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/ocr_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

const _provider = AgentProviderConfig(
  id: 'p1',
  kind: AgentProviderKind.openAiCompatible,
  displayName: 'Test',
  baseUrl: 'https://example.invalid',
  smallModel: 'small',
  complexModel: 'large',
  supportsStreaming: false,
);

const _analysisJson = <String, Object?>{
  'schema': 'rikai.agent.analysis.v1',
  'source_id': 'src-1',
  'translation': <Object?>[
    <String, Object?>{'quote_id': 'q1', 'text': '请多关照。', 'label': '模型译文'},
  ],
  'segments': <Object?>[
    <String, Object?>{
      'id': 'seg-1',
      'quote_id': 'q1',
      'literal': '何卒',
      'interpretation': '正式请求',
      'epistemic': 'dictionary_fact',
      'word_notes': <Object?>[
        <String, Object?>{
          'token_id': 't1',
          'surface': '何卒',
          'sense': '请务必',
          'citation_ids': <String>['source-1'],
        },
      ],
    },
  ],
  'interpretations': <Object?>[],
  'unresolved': <Object?>[],
  'citations_used': <String>['source-1'],
  'model_supplements': <Object?>[],
};

class _FakeOcr implements OcrPort {
  int calls = 0;

  @override
  bool get horizontalAvailable => true;

  @override
  bool get verticalAvailable => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> ensureReady() async {}

  @override
  Future<OcrRun> recognize({
    required OcrHandle image,
    required OcrMode mode,
  }) async {
    calls++;
    return const OcrRun(
      engine: 'paddle_v5',
      mode: OcrMode.auto,
      text: '何卒',
      elapsedMs: 1,
      confidence: 0.99,
    );
  }
}

class _FakeTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '副詞';
    features[7] = '何卒';
    features[8] = '何卒';
    features[20] = 'ナニトゾ';
    return <Token>[
      Token.fromFeatures(surface: '何卒', features: features, start: 0, end: 2),
    ];
  }
}

class _FakeLookup implements LookupPort {
  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: const <LookupEntry>[
            LookupEntry(matchedKey: '何卒', headword: '何卒', html: '<b>なにとぞ</b>'),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    return const <String>[];
  }
}

AgentOrchestrator _orchestrator({
  required FakeProvider provider,
  _FakeOcr? ocr,
}) {
  return AgentOrchestrator(
    ocrPort: ocr ?? _FakeOcr(),
    tokenizePort: _FakeTokenize(),
    lookupPort: _FakeLookup(),
    grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
    citations: CitationRegistry(),
    llmFactory: (_) => provider,
  );
}

void main() {
  test('runs the fixed pipeline and returns cited evidence', () async {
    final provider = FakeProvider(responseText: jsonEncode(_analysisJson));
    final stages = <AgentStage>[];
    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        userText: '何卒',
      ),
      onStage: (stage, message) => stages.add(stage),
    );

    expect(result.analysis.sourceId, 'src-1');
    expect(result.citations, hasLength(1));
    expect(result.validation.valid, isTrue);
    expect(result.quotes.single.text, '何卒');
    expect(stages, contains(AgentStage.done));
    expect(provider.requests, hasLength(1));
    final requestText = provider.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(requestText.contains('何卒'), isTrue);
    expect(requestText.contains('/sdcard'), isFalse);
  });

  test('OCR image paths are never placed in the provider request', () async {
    final provider = FakeProvider(responseText: jsonEncode(_analysisJson));
    final ocr = _FakeOcr();
    await _orchestrator(provider: provider, ocr: ocr).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        images: <AgentImageInput>[
          AgentImageInput(
            id: 'img-1',
            localPath: '/sdcard/Download/private-page.jpg',
          ),
        ],
      ),
    );

    expect(ocr.calls, 1);
    final requestText = provider.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(requestText.contains('img-1'), isTrue);
    expect(requestText.contains('/sdcard'), isFalse);
    expect(requestText.contains('private-page.jpg'), isFalse);
  });

  test(
    'image plus instruction keeps the instruction out of evidence sources',
    () async {
      final provider = FakeProvider(responseText: jsonEncode(_analysisJson));
      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '请解释这句话',
          images: <AgentImageInput>[
            AgentImageInput(
              id: 'img-1',
              localPath: '/sdcard/Download/page.jpg',
            ),
          ],
        ),
      );

      expect(result.input.userText, '请解释这句话');
      expect(result.input.sources, hasLength(1));
      expect(result.evidence.sources, hasLength(1));
      expect(result.evidence.sources.single.kind, 'image_ocr');
    },
  );

  test('strict validation failure is repaired without redoing OCR/lookup', () async {
    final bad = Map<String, Object?>.from(_analysisJson)
      ..['segments'] = <Object?>[
        <String, Object?>{
          'id': 'seg-1',
          'quote_id': 'q1',
          'interpretation': '无依据',
          'epistemic': 'dictionary_fact',
          'word_notes': <Object?>[
            <String, Object?>{'token_id': 't1', 'surface': '何卒', 'sense': '随便'},
          ],
        },
      ];
    final provider = FakeProvider(
      responseSequence: <String>[
        jsonEncode(bad),
        jsonEncode(_analysisJson),
      ],
    );

    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        userText: '何卒',
      ),
    );

    expect(result.validation.valid, isTrue);
    expect(result.analysis.segments, isNotEmpty);
    expect(provider.requests, hasLength(2));
    final repairPrompt = provider.requests.last.messages
        .map((message) => message.text)
        .join('\n');
    expect(repairPrompt.contains('Validation errors'), isTrue);
    expect(repairPrompt.contains('Previous output'), isTrue);
  });

  test('unrepaired output is salvaged instead of being thrown away', () async {
    final bad = Map<String, Object?>.from(_analysisJson)
      ..['segments'] = <Object?>[
        <String, Object?>{
          'id': 'seg-1',
          'quote_id': 'q1',
          'interpretation': '无依据',
          'epistemic': 'dictionary_fact',
          'word_notes': <Object?>[
            <String, Object?>{'token_id': 't1', 'surface': '何卒', 'sense': '随便'},
          ],
        },
      ];
    final provider = FakeProvider(responseText: jsonEncode(bad));

    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        userText: '何卒',
      ),
    );

    expect(result.validation.valid, isFalse);
    expect(result.validation.errors, isNotEmpty);
    expect(result.analysis.translation, isNotEmpty);
    expect(result.analysis.segments, isEmpty);
    expect(result.analysis.unresolved, isNotEmpty);
    expect(provider.requests, hasLength(2));
  });
}
