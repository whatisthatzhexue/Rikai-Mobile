import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_match_mode.dart';
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

const _coverageMissing = '''
{"schema":"rikai.agent.coverage.v1","source_id":"src-1","verdict":"missing",
 "missing":[{"kind":"usage","query":"何卒","source_refs":["t1"],
             "reason":"缺少用法","priority":1}],
 "duplicate_groups":[]}
''';

const _coverageDuplicate = '''
{"schema":"rikai.agent.coverage.v1","source_id":"src-1","verdict":"missing",
 "missing":[{"kind":"usage","query":"何卒","source_refs":["t1"],
             "reason":"缺少用法","priority":1}],
 "duplicate_groups":[{"dictionary_id":"dict_a","keep_entry_key":"何卒",
                      "remove_entry_keys":["何卒（副）"],"reason":"重复"}]}
''';

class _FakeOcr implements OcrPort {
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
    throw StateError('OCR is not used in text runs');
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

class _LookupScript implements LookupPort {
  _LookupScript(this.exactResponses);

  final List<List<LookupEntry>> exactResponses;
  var _exactCalls = 0;

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    if (request.matchMode != LookupMatchMode.exact) {
      return LookupResult(
        query: request.query,
        candidates: request.rawCandidates,
        groups: const <DictionaryLookupGroup>[],
      );
    }
    final index = _exactCalls;
    _exactCalls++;
    final entries = exactResponses[index.clamp(0, exactResponses.length - 1)];
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: entries,
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

LookupEntry _entry(String key, String html) =>
    LookupEntry(matchedKey: key, headword: key, html: html);

AgentOrchestrator _orchestrator({
  required FakeProvider provider,
  required LookupPort lookup,
  required AgentLimits limits,
}) {
  return AgentOrchestrator(
    ocrPort: _FakeOcr(),
    tokenizePort: _FakeTokenize(),
    lookupPort: lookup,
    grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
    citations: CitationRegistry(),
    llmFactory: (_) => provider,
    limits: limits,
  );
}

void main() {
  test('flow A adds traceable missing evidence once', () async {
    final lookup = _LookupScript(<List<LookupEntry>>[
      <LookupEntry>[_entry('何卒', 'なにとぞ。どうか。')],
      <LookupEntry>[_entry('何卒・用法', '正式な依頼に使う表現。')],
    ]);
    final provider = FakeProvider(
      responseSequence: <String>[_coverageMissing, _analysisTagged],
    );
    final stages = <AgentStage>[];

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          limits: const AgentLimits(maxCoverageFallback: 1),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
          onStage: (stage, message) => stages.add(stage),
        );

    expect(stages, contains(AgentStage.coverage));
    expect(result.coverageFallbackUsed, isTrue);
    expect(result.evidence.citations, hasLength(2));
    expect(
      result.evidence.sources.single.tokens.single.citationIds,
      hasLength(2),
    );
    expect(result.warnings, isNot(contains('覆盖审查不可用，已保留现有资料')));
    expect(provider.requests, hasLength(2));
  });

  test('flow B prunes a verified duplicate before supplementing', () async {
    final lookup = _LookupScript(<List<LookupEntry>>[
      <LookupEntry>[
        _entry('何卒', 'なにとぞ。どうか。正式な依頼に使う表現。'),
        _entry('何卒（副）', 'なにとぞ。どうか。'),
      ],
      <LookupEntry>[_entry('何卒・追加', '正式な依頼に用いる。')],
    ]);
    final provider = FakeProvider(
      responseSequence: <String>[_coverageDuplicate, _analysisTagged],
    );

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          limits: const AgentLimits(
            maxEvidenceEntries: 2,
            maxCoverageFallback: 1,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(result.coverageFallbackUsed, isTrue);
    expect(result.evidence.citations, hasLength(2));
    expect(
      result.evidence.citations.map((citation) => citation.entryKey),
      isNot(contains('何卒（副）')),
    );
    expect(
      result.evidence.citations.map((citation) => citation.entryKey),
      contains('何卒・追加'),
    );
  });

  test('a failed coverage review keeps evidence and warns', () async {
    final lookup = _LookupScript(<List<LookupEntry>>[
      <LookupEntry>[_entry('何卒', 'なにとぞ。どうか。')],
    ]);
    final provider = FakeProvider(
      responseSequence: <String>[
        'not coverage json',
        'still not coverage json',
        _analysisTagged,
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          limits: const AgentLimits(maxCoverageFallback: 1),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(result.coverageFallbackUsed, isFalse);
    expect(result.evidence.citations, hasLength(1));
    expect(result.warnings, contains('覆盖审查不可用，已保留现有资料'));
    expect(provider.requests, hasLength(3));
  });
}
