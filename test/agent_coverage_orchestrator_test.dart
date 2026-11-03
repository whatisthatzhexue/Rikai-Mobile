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
[COVERAGE verdict="missing"]
[MISSING kind="usage" query="何卒" refs="t1" priority="1"]缺少用法[/MISSING]
[/COVERAGE]
''';

const _coverageDuplicate = '''
[COVERAGE verdict="missing"]
[MISSING kind="usage" query="何卒" refs="t1" priority="1"]缺少用法[/MISSING]
[DUPLICATE dictionary="dict_a" keep="何卒" remove="何卒（副）"]重复[/DUPLICATE]
[/COVERAGE]
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
    String? engine,
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

class _TwoTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    Token make(String surface, String reading, int start, int end) {
      final features = List<String>.filled(Token.expectedFeatureCount, '*');
      features[0] = '副詞';
      features[7] = surface;
      features[8] = surface;
      features[20] = reading;
      return Token.fromFeatures(
        surface: surface,
        features: features,
        start: start,
        end: end,
      );
    }

    return <Token>[make('何卒', 'ナニトゾ', 0, 2), make('宜しく', 'ヨロシク', 2, 5)];
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
  TokenizePort? tokenize,
}) {
  return AgentOrchestrator(
    ocrPort: _FakeOcr(),
    tokenizePort: tokenize ?? _FakeTokenize(),
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
          limits: const AgentLimits(
            maxCoverageFallback: 1,
            adaptiveCoverageReview: false,
            enableRichTextPostProcess: false,
          ),
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

  test('coverage tag integrity failure gets one format repair', () async {
    final lookup = _LookupScript(<List<LookupEntry>>[
      <LookupEntry>[_entry('何卒', 'なにとぞ。どうか。')],
      <LookupEntry>[_entry('何卒・用法', '正式な依頼に使う表現。')],
    ]);
    final provider = FakeProvider(
      responseSequence: <String>[
        '```text\n$_coverageMissing[/COVERAGE]\n```',
        _coverageMissing,
        _analysisTagged,
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          limits: const AgentLimits(
            maxCoverageFallback: 1,
            adaptiveCoverageReview: false,
            enableRichTextPostProcess: false,
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
    expect(provider.requests, hasLength(3));
    final repairPrompt = provider.requests[1].messages
        .map((message) => message.text)
        .join('\n');
    expect(repairPrompt, contains('FORMAT CORRECTION TASK'));
    expect(repairPrompt, contains('多余的结束标签 [/COVERAGE]'));
    // The repair request must use the normalized response, not the raw one,
    // so a wrapper error fixed by normalization cannot repeat.
    expect(repairPrompt, isNot(contains('```')));
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
            adaptiveCoverageReview: false,
            enableRichTextPostProcess: false,
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
        'not coverage tags',
        'still not coverage tags',
        _analysisTagged,
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          limits: const AgentLimits(
            maxCoverageFallback: 1,
            adaptiveCoverageReview: false,
            enableRichTextPostProcess: false,
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

    expect(result.coverageFallbackUsed, isFalse);
    expect(result.evidence.citations, hasLength(1));
    expect(result.warnings, contains('覆盖审查不可用，已保留现有资料'));
    expect(provider.requests, hasLength(3));
  });

  test(
    'adaptive coverage skips when every target already has a citation',
    () async {
      final lookup = _LookupScript(<List<LookupEntry>>[
        <LookupEntry>[_entry('何卒', 'なにとぞ。どうか。')],
      ]);
      final provider = FakeProvider(
        responseSequence: <String>[_analysisTagged],
      );
      final stages = <AgentStage>[];

      final result =
          await _orchestrator(
            provider: provider,
            lookup: lookup,
            limits: const AgentLimits(
              maxCoverageFallback: 1,
              enableRichTextPostProcess: false,
            ),
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

      expect(stages, isNot(contains(AgentStage.coverage)));
      expect(result.coverageFallbackUsed, isFalse);
      expect(result.evidence.citations, hasLength(1));
      expect(provider.requests, hasLength(1));
    },
  );

  test(
    'adaptive coverage runs when a target lacks citation despite total count',
    () async {
      final lookup = _LookupScript(<List<LookupEntry>>[
        <LookupEntry>[
          _entry('何卒', 'なにとぞ。どうか。'),
          _entry('何卒（副）', '副詞的な用法。'),
          _entry('何卒（感）', '感叹用法。'),
        ],
        const <LookupEntry>[],
      ]);
      final provider = FakeProvider(
        responseSequence: <String>[_coverageMissing, _analysisTagged],
      );
      final stages = <AgentStage>[];

      final result =
          await _orchestrator(
            provider: provider,
            lookup: lookup,
            tokenize: _TwoTokenize(),
            limits: const AgentLimits(
              maxCoverageFallback: 1,
              enableRichTextPostProcess: false,
            ),
          ).run(
            const AgentRunRequest(
              sessionId: 's1',
              mode: AgentMode.strict,
              dictionaries: <DictionaryInfo>[_dictionary],
              provider: _provider,
              userText: '何卒宜しく',
            ),
            onStage: (stage, message) => stages.add(stage),
          );

      expect(stages, contains(AgentStage.coverage));
      expect(result.coverageFallbackUsed, isTrue);
      expect(
        result.evidence.budget.targetsWithCitations,
        lessThan(result.evidence.budget.uniqueTargets),
      );
      expect(provider.requests.first.messages.first.text, contains('COVERAGE'));
    },
  );
}
