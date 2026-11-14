import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_input.dart';
import 'package:lexicandy/core/models/agent/agent_limits.dart';
import 'package:lexicandy/core/models/agent/agent_provider.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/models/lookup_match_mode.dart';
import 'package:lexicandy/core/models/lookup_models.dart';
import 'package:lexicandy/core/models/lookup_request.dart';
import 'package:lexicandy/core/models/token.dart';
import 'package:lexicandy/services/agent/agent_orchestrator.dart';
import 'package:lexicandy/services/agent/agent_run.dart';
import 'package:lexicandy/services/agent/citation_registry.dart';
import 'package:lexicandy/services/agent/grammar_patterns.dart';
import 'package:lexicandy/services/agent/ports/lookup_port.dart';
import 'package:lexicandy/services/agent/ports/ocr_port.dart';
import 'package:lexicandy/services/agent/ports/tokenize_port.dart';
import 'package:lexicandy/services/agent/providers/fake_provider.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

const _dictionaryB = DictionaryInfo(
  id: 'dict_b',
  title: 'B',
  mdxPath: '/b.mdx',
  order: 1,
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

const _fanOutA = '''
[TRANSLATION quote="q1"]A译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]A义[/MEANING]
[WORD id="t1"]何卒||A|source-1[/WORD]
[/SEGMENT]
''';

const _fanOutB = '''
[TRANSLATION quote="q1"]B译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]B义[/MEANING]
[WORD id="t1"]何卒||B|source-2[/WORD]
[/SEGMENT]
''';

const _plainAnalysis = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="inference" quote="q1"]
[MEANING]语境推断[/MEANING]
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

const _coverageCompound = '''
[COVERAGE verdict="missing"]
[MISSING kind="word" query="ところが" refs="t1,t2" priority="1"]整体词条[/MISSING]
[/COVERAGE]
''';

const _compoundAnalysis = '''
[TRANSLATION quote="q1"]然而[/TRANSLATION]
[SEGMENT type="inference" quote="q1"]
[MEANING]转折关系[/MEANING]
[/SEGMENT]
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

class _FiveContentTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    return <Token>[
      for (var index = 1; index <= 5; index++)
        Token.fromFeatures(
          surface: '語$index',
          features: <String>[
            '名詞',
            ...List<String>.filled(6, '*'),
            '語$index',
            '語$index',
            '*',
            '語$index',
            ...List<String>.filled(9, '*'),
            'ゴ$index',
            ...List<String>.filled(8, '*'),
          ],
          start: index * 2,
          end: index * 2 + 2,
        ),
    ];
  }
}

class _CompoundTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    Token make(String surface, String pos, int start, int end) {
      final features = List<String>.filled(Token.expectedFeatureCount, '*');
      features[0] = pos;
      features[7] = surface;
      features[8] = surface;
      features[20] = surface;
      return Token.fromFeatures(
        surface: surface,
        features: features,
        start: start,
        end: end,
      );
    }

    return <Token>[make('ところ', '名詞', 0, 3), make('が', '助詞', 3, 4)];
  }
}

class _LookupScript implements LookupPort {
  _LookupScript(this.exactResponses);

  final List<List<LookupEntry>> exactResponses;
  final List<String> exactQueries = <String>[];
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
    exactQueries.add(request.query);
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

class _MultiDictionaryLookup implements LookupPort {
  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        for (final dictionary in request.dictionaries)
          DictionaryLookupGroup(
            dictionary: dictionary,
            entries: <LookupEntry>[_entry('何卒', 'なにとぞ。')],
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
    // One content target + the bounded coverage reserve, not the global 60.
    expect(result.evidence.budget.maxCitations, 7);
    expect(
      result.evidence.sources.single.tokens.single.citationIds,
      hasLength(2),
    );
    expect(result.warnings, isNot(contains('覆盖审查不可用，已保留现有资料')));
    expect(provider.requests, hasLength(2));
    final coveragePrompt = provider.requests.first.messages
        .map((message) => message.text)
        .join('\n');
    expect(coveragePrompt, isNot(contains('"start":')));
    expect(coveragePrompt, isNot(contains('"dictionary_title":')));
    expect(coveragePrompt, contains('"entry_key":'));
  });

  test('flow C supplements a traceable compound query once', () async {
    final lookup = _LookupScript(<List<LookupEntry>>[
      <LookupEntry>[],
      <LookupEntry>[_entry('ところが', 'しかし。ところが。')],
    ]);
    final provider = FakeProvider(
      responseSequence: <String>[_coverageCompound, _compoundAnalysis],
    );

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          tokenize: _CompoundTokenize(),
          limits: const AgentLimits(
            maxCoverageFallback: 1,
            adaptiveCoverageReview: false,
            enableRichTextPostProcess: false,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.loose,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: 'ところが',
          ),
        );

    expect(lookup.exactQueries.where((query) => query == 'ところが'), hasLength(1));
    expect(result.coverageFallbackUsed, isTrue);
    expect(result.evidence.citations, hasLength(1));
    expect(result.evidence.citations.single.entryKey, 'ところが');
    expect(
      result.evidence.sources.single.tokens[0].citationIds,
      contains('source-1'),
    );
    expect(
      result.evidence.sources.single.tokens[1].citationIds,
      contains('source-1'),
    );
    expect(provider.requests, hasLength(2));
    expect(result.telemetry.llmCalls, 2);
    expect(result.telemetry.analysisCalls, 1);
    expect(result.telemetry.coverageCalls, 1);
    // ところ is the only content word; が is a particle and is excluded.
    expect(result.telemetry.targetCount, 1);
    expect(result.telemetry.targetsWithCitations, 1);
    expect(result.telemetry.citationCoverage, 1);
  });

  test(
    'five dictionaries and ten sentences still use one analysis call',
    () async {
      final lookup = _LookupScript(<List<LookupEntry>>[<LookupEntry>[]]);
      final provider = FakeProvider(responseSequence: <String>[_plainAnalysis]);
      const dictionaries = <DictionaryInfo>[
        DictionaryInfo(id: 'd1', title: 'D1', mdxPath: '/d1.mdx', order: 0),
        DictionaryInfo(id: 'd2', title: 'D2', mdxPath: '/d2.mdx', order: 1),
        DictionaryInfo(id: 'd3', title: 'D3', mdxPath: '/d3.mdx', order: 2),
        DictionaryInfo(id: 'd4', title: 'D4', mdxPath: '/d4.mdx', order: 3),
        DictionaryInfo(id: 'd5', title: 'D5', mdxPath: '/d5.mdx', order: 4),
      ];
      final userText = '何卒宜しく。${List<String>.filled(9, 'これはテストです。').join()}';

      final result =
          await _orchestrator(
            provider: provider,
            lookup: lookup,
            limits: const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
          ).run(
            AgentRunRequest(
              sessionId: 's1',
              mode: AgentMode.loose,
              dictionaries: dictionaries,
              provider: _provider,
              userText: userText,
            ),
          );

      // Ten sentences and five dictionaries must not fan out into per-sentence
      // or per-dictionary analysis calls.
      expect(provider.requests, hasLength(1));
      final prompt = provider.requests.single.messages
          .map((message) => message.text)
          .join('\n');
      expect(prompt, contains('Local request hint'));
      expect(prompt, contains('likely tasks: explanation'));
      expect(result.telemetry.llmCalls, 1);
      expect(result.telemetry.analysisCalls, 1);
      expect(result.telemetry.coverageCalls, 0);
      expect(result.telemetry.repairCalls, 0);
      expect(result.telemetry.languageRepairCalls, 0);
      expect(result.telemetry.inputChars, greaterThan(0));
      expect(result.telemetry.outputChars, greaterThan(0));
      expect(result.telemetry.targetCount, greaterThan(0));
      expect(result.telemetry.citationCount, 0);
      expect(result.telemetry.targetsWithCitations, 0);
      expect(result.telemetry.citationCoverage, 0);
    },
  );

  test('dictionary fan-out merges per-dictionary analyses in order', () async {
    final provider = FakeProvider(
      responseSequence: <String>[_fanOutA, _fanOutB],
    );

    final result =
        await _orchestrator(
          provider: provider,
          lookup: _MultiDictionaryLookup(),
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: false,
            enableDictionaryFanOut: true,
            dictionaryFanOutThreshold: 1,
            dictionaryFanOutConcurrency: 1,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary, _dictionaryB],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(provider.requests, hasLength(2));
    expect(result.validation.valid, isTrue);
    expect(result.analysis.translation.single.text, 'A译文');
    expect(result.analysis.segments, hasLength(1));
    expect(result.analysis.segments.single.id, 's1');
    expect(result.analysis.segments.single.wordNotes, hasLength(2));
    expect(
      result.analysis.citationsUsed,
      containsAll(<String>['source-1', 'source-2']),
    );
    expect(result.evidence.citations, hasLength(2));
    expect(result.telemetry.llmCalls, 2);
    expect(result.telemetry.analysisCalls, 2);
    expect(result.telemetry.coverageCalls, 0);
    expect(result.telemetry.repairCalls, 0);
    expect(result.telemetry.targetCount, 1);
    expect(result.telemetry.targetsWithCitations, 1);
    expect(result.warnings, isNot(contains('部分词典分析失败，已保留其余结果')));
  });

  test(
    'dictionary fan-out keeps the other result when one call fails',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>['not tagged', _fanOutB],
      );

      final result =
          await _orchestrator(
            provider: provider,
            lookup: _MultiDictionaryLookup(),
            limits: const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
              enableDictionaryFanOut: true,
              dictionaryFanOutThreshold: 1,
              dictionaryFanOutConcurrency: 1,
            ),
          ).run(
            const AgentRunRequest(
              sessionId: 's1',
              mode: AgentMode.strict,
              dictionaries: <DictionaryInfo>[_dictionary, _dictionaryB],
              provider: _provider,
              userText: '何卒',
            ),
          );

      expect(provider.requests, hasLength(2));
      expect(result.validation.valid, isTrue);
      expect(result.analysis.translation.single.text, 'B译文');
      expect(result.analysis.segments.single.wordNotes, hasLength(1));
      expect(result.warnings, contains('部分词典分析失败，已保留其余结果'));
    },
  );

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

  test('coverage skips at 80% content-word citation coverage', () async {
    final lookup = _LookupScript(<List<LookupEntry>>[
      <LookupEntry>[_entry('語1', '一')],
      <LookupEntry>[_entry('語2', '二')],
      <LookupEntry>[_entry('語3', '三')],
      <LookupEntry>[_entry('語4', '四')],
      const <LookupEntry>[],
    ]);
    final provider = FakeProvider(responseText: _plainAnalysis);

    final result =
        await _orchestrator(
          provider: provider,
          lookup: lookup,
          tokenize: _FiveContentTokenize(),
          limits: const AgentLimits(
            maxCoverageFallback: 1,
            adaptiveCoverageReview: true,
            enableRichTextPostProcess: false,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.loose,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '語1語2語3語4語5',
          ),
        );

    expect(result.evidence.citations, hasLength(4));
    // 4/5 content words = 80%, so coverage is skipped.
    expect(provider.requests, hasLength(1));
    expect(result.telemetry.coverageCalls, 0);
  });
}
