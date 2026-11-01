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

const _analysisTagged = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';

const _analysisWithoutCitation = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]无依据[/MEANING]
[/SEGMENT]
''';

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
    final provider = FakeProvider(responseText: _analysisTagged);
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
    final provider = FakeProvider(responseText: _analysisTagged);
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
      final provider = FakeProvider(responseText: _analysisTagged);
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

  test(
    'strict validation failure is repaired without redoing OCR/lookup',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[_analysisWithoutCitation, _analysisTagged],
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
    },
  );

  test(
    'tagged output repairs a broken format without redoing evidence',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[
          'This is not a tagged response.',
          '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''',
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
      expect(result.analysis.translation.single.text, '请多关照。');
      expect(provider.requests, hasLength(2));
      final repairPrompt = provider.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairPrompt, contains('FORMAT CORRECTION TASK'));
      expect(repairPrompt, contains('Previous output'));
    },
  );

  test(
    'orphan tag triggers one format repair even when content parses',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[
          '$_analysisTagged[/SEGMENT]',
          _analysisTagged,
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
      expect(provider.requests, hasLength(2));
      final repairPrompt = provider.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairPrompt, contains('多余的结束标签 [/SEGMENT]'));
    },
  );

  test('unrepaired tag integrity failure is reported, not accepted', () async {
    final provider = FakeProvider(responseText: '$_analysisTagged[/SEGMENT]');

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
    expect(
      result.validation.errors.any(
        (error) => error.contains('多余的结束标签 [/SEGMENT]'),
      ),
      isTrue,
    );
    expect(result.analysis.translation, isNotEmpty);
    expect(provider.requests, hasLength(2));
  });

  test('unrepaired output is salvaged instead of being thrown away', () async {
    final provider = FakeProvider(responseText: _analysisWithoutCitation);

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
