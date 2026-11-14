import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_evidence.dart';
import 'package:lexicandy/core/models/agent/agent_input.dart';
import 'package:lexicandy/core/models/agent/agent_ocr.dart';
import 'package:lexicandy/core/models/agent/agent_quote.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/models/lookup_models.dart';
import 'package:lexicandy/core/models/lookup_request.dart';
import 'package:lexicandy/core/models/token.dart';
import 'package:lexicandy/services/agent/ocr_consensus.dart';
import 'package:lexicandy/services/agent/ports/lookup_port.dart';
import 'package:lexicandy/services/agent/ports/tokenize_port.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

AgentOcrVariant _variant({
  required String id,
  required String text,
  double confidence = 0.9,
  OcrMode mode = OcrMode.auto,
}) {
  return AgentOcrVariant(
    id: id,
    engine: 'paddle_v5',
    mode: mode,
    text: text,
    confidence: confidence,
  );
}

class _FakeTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    final surfaces = <String>['何卒', 'コンニチハ', 'テスト'];
    return <Token>[
      for (var index = 0; index < surfaces.length; index++)
        Token.fromFeatures(
          surface: surfaces[index],
          features: _features(surfaces[index]),
          start: index,
          end: index + 1,
        ),
    ];
  }

  static List<String> _features(String surface) {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '名詞';
    features[7] = surface;
    features[8] = surface;
    features[20] = surface;
    return features;
  }
}

class _FakeLookup implements LookupPort {
  _FakeLookup({required this.hits, this.suggestions = const <String>[]});

  final Set<String> hits;
  final List<String> suggestions;
  int suggestCalls = 0;

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    final hit = hits.contains(request.query);
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: hit
              ? <LookupEntry>[
                  LookupEntry(
                    matchedKey: request.query,
                    headword: request.query,
                    html: '<b>${request.query}</b>',
                  ),
                ]
              : const <LookupEntry>[],
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
    suggestCalls++;
    return suggestions;
  }
}

void main() {
  group('OcrQuality', () {
    test('short or low-confidence text is low quality', () {
      expect(
        OcrConsensus.assess(
          variant: _variant(id: 'v1', text: '。'),
        ).isLowQuality,
        isTrue,
      );
      expect(
        OcrConsensus.assess(
          variant: _variant(id: 'v2', text: '何卒', confidence: 0.5),
        ).isLowQuality,
        isTrue,
      );
    });

    test('repeated OCR noise is detected', () {
      final quality = OcrConsensus.assess(
        variant: _variant(id: 'v1', text: 'あああああ'),
      );
      expect(quality.duplicateNoiseRatio, greaterThan(0));
      expect(quality.isLowQuality, isTrue);
    });

    test('dictionary hit rate flags content words with no citations', () {
      final quality = OcrConsensus.assess(
        variant: _variant(id: 'v1', text: '何卒'),
        dictionaryHitRate: 0.25,
        contentWords: 4,
      );
      expect(quality.hasDictionarySignal, isTrue);
      expect(quality.isLowQuality, isTrue);
      expect(quality.rankScore, lessThan(0.8));
    });

    test('higher confidence and hit rate rank a variant higher', () {
      final low = OcrConsensus.assess(
        variant: _variant(id: 'low', text: '何卒', confidence: 0.6),
        dictionaryHitRate: 0.2,
        contentWords: 5,
      );
      final high = OcrConsensus.assess(
        variant: _variant(id: 'high', text: '何卒', confidence: 0.95),
        dictionaryHitRate: 0.8,
        contentWords: 5,
      );
      expect(high.rankScore, greaterThan(low.rankScore));
    });

    test('evidence-based assessment counts content tokens with citations', () {
      final quality = OcrConsensus.assessWithEvidence(
        variant: _variant(id: 'v1', text: '何卒'),
        evidence: const AgentSourceEvidence(
          id: 'src-1',
          kind: 'image_ocr',
          text: '何卒',
          tokens: <AgentTokenEvidence>[
            AgentTokenEvidence(
              id: 't1',
              surface: '何卒',
              start: 0,
              end: 2,
              content: true,
              citationIds: <String>['source-1'],
            ),
            AgentTokenEvidence(
              id: 't2',
              surface: 'テスト',
              start: 2,
              end: 5,
              content: true,
            ),
            AgentTokenEvidence(
              id: 't3',
              surface: 'です',
              start: 5,
              end: 7,
              content: false,
            ),
          ],
        ),
      );
      expect(quality.contentWords, 2);
      expect(quality.dictionaryHitRate, 0.5);
    });
  });

  group('OcrTextDiff', () {
    test('identical text has no changed spans', () {
      final diff = OcrConsensus.diff('何卒宜しく', '何卒宜しく');
      expect(diff.identical, isTrue);
      expect(diff.baseChangedChars, 0);
      expect(diff.candidateChangedChars, 0);
      expect(diff.baseSpans.map((span) => span.text).join(), '何卒宜しく');
    });

    test('single-character replacement keeps correct offsets', () {
      final diff = OcrConsensus.diff('何卒宣しく', '何卒宜しく');
      expect(diff.baseChangedChars, 1);
      expect(diff.candidateChangedChars, 1);
      final changed = diff.changedBaseSpans.single;
      expect(changed.text, '宣');
      expect(changed.start, 2);
      expect(changed.end, 3);
      expect(diff.candidateSpans.map((span) => span.text).join(), '何卒宜しく');
    });

    test('insertion marks only the candidate side as changed', () {
      final diff = OcrConsensus.diff('何卒', '何卒です');
      expect(diff.baseChangedChars, 0);
      expect(diff.candidateChangedChars, 2);
      final changed = diff.changedCandidateSpans.single;
      expect(changed.text, 'です');
      expect(changed.start, 2);
      expect(changed.end, 4);
    });

    test('large changed middle is bounded to one span', () {
      final base = 'a' * 300;
      final candidate = 'b' * 300;
      final diff = OcrConsensus.diff(base, candidate);
      expect(diff.changedBaseSpans, hasLength(1));
      expect(diff.changedBaseSpans.single.start, 0);
      expect(diff.changedBaseSpans.single.end, 300);
      expect(diff.baseChangedChars, 300);
    });

    test('text beyond the diff limit remains visible as an unchanged tail', () {
      final base = '${'あ' * 10}${'い' * 10}';
      final diff = OcrConsensus.diff(
        base,
        '${'あ' * 10}${'う' * 10}',
        maxChars: 12,
      );
      expect(diff.baseSpans.map((span) => span.text).join(), base);
      expect(diff.baseSpans.last.end, base.length);
    });
  });

  group('OcrConsensus.compare', () {
    test('recommends the better variant but keeps a tie on the baseline', () {
      final baseline = _variant(id: 'base', text: '何卒', confidence: 0.8);
      final better = _variant(id: 'better', text: '何卒', confidence: 0.95);
      final view = OcrConsensus.compare(
        baseline: baseline,
        variants: <AgentOcrVariant>[better],
      );
      expect(view.recommendedVariantId, 'better');
      expect(view.comparisons, hasLength(2));

      final tie = OcrConsensus.compare(
        baseline: baseline,
        variants: <AgentOcrVariant>[
          _variant(id: 'tie', text: '何卒', confidence: 0.8),
        ],
      );
      expect(tie.recommendedVariantId, 'base');
    });

    test('dictionary hit rate can outweigh raw confidence', () {
      final baseline = _variant(id: 'base', text: '何卒', confidence: 0.95);
      final better = _variant(id: 'better', text: '何卒', confidence: 0.8);
      final view = OcrConsensus.compare(
        baseline: baseline,
        variants: <AgentOcrVariant>[better],
        qualityById: <String, OcrQuality>{
          'base': OcrConsensus.assess(
            variant: baseline,
            dictionaryHitRate: 0.2,
            contentWords: 6,
          ),
          'better': OcrConsensus.assess(
            variant: better,
            dictionaryHitRate: 0.9,
            contentWords: 6,
          ),
        },
      );
      expect(view.recommendedVariantId, 'better');
    });
  });

  group('dictionary-assisted repair', () {
    test('measures bounded dictionary hits for content words', () async {
      final result = await OcrConsensus.measureDictionaryHits(
        text: '何卒コンニチハテスト',
        tokenizePort: _FakeTokenize(),
        lookupPort: _FakeLookup(hits: <String>{'何卒'}),
        dictionaries: const <DictionaryInfo>[_dictionary],
      );
      expect(result, isNotNull);
      expect(result!.words, 3);
      expect(result.rate, closeTo(1 / 3, 0.0001));
    });

    test('suggests a dictionary candidate for a changed chunk', () async {
      final diff = OcrConsensus.diff('何卒コンニチハ', '何卒コンバンハ');
      final lookup = _FakeLookup(
        hits: const <String>{},
        suggestions: const <String>['ニッポン'],
      );
      final suggestions = await OcrConsensus.suggestRepairs(
        text: '何卒コンニチハ',
        diff: diff,
        dictionaries: const <DictionaryInfo>[_dictionary],
        lookupPort: lookup,
      );
      expect(suggestions, isNotEmpty);
      expect(suggestions.single.original, 'ニチ');
      expect(suggestions.single.candidates.single.text, 'ニッポン');
      expect(lookup.suggestCalls, greaterThan(0));
    });

    test(
      'does not suggest repairs for a word already in the dictionary',
      () async {
        final diff = OcrConsensus.diff('何卒コンニチハ', '何卒コンバンハ');
        final lookup = _FakeLookup(
          hits: const <String>{'ニチ'},
          suggestions: const <String>['ニッポン'],
        );
        final suggestions = await OcrConsensus.suggestRepairs(
          text: '何卒コンニチハ',
          diff: diff,
          dictionaries: const <DictionaryInfo>[_dictionary],
          lookupPort: lookup,
        );
        expect(suggestions, isEmpty);
        expect(lookup.suggestCalls, 0);
      },
    );

    test(
      'applyRepair creates a dictionary-repair variant without mutation',
      () {
        final baseline = _variant(id: 'base', text: '何卒コンニチハ');
        final repaired = OcrConsensus.applyRepair(
          baseline: baseline,
          suggestion: const OcrRepairSuggestion(
            original: 'ニチ',
            start: 4,
            end: 6,
            candidates: <OcrRepairCandidate>[OcrRepairCandidate(text: 'バン')],
          ),
          candidate: const OcrRepairCandidate(text: 'バン'),
          id: 'repair-1',
        );
        expect(repaired, isNotNull);
        expect(repaired!.text, '何卒コンバンハ');
        expect(repaired.origin, AgentQuoteOrigin.dictionaryRepair);
        expect(repaired.engine, 'dictionary_repair');
        expect(baseline.text, '何卒コンニチハ');

        final multi = OcrConsensus.applyRepairs(
          baseline: baseline,
          selections: const <OcrRepairSelection>[
            OcrRepairSelection(
              suggestion: OcrRepairSuggestion(
                original: 'ニチ',
                start: 4,
                end: 6,
                candidates: <OcrRepairCandidate>[
                  OcrRepairCandidate(text: 'パン'),
                ],
              ),
              candidate: OcrRepairCandidate(text: 'パン'),
            ),
            OcrRepairSelection(
              suggestion: OcrRepairSuggestion(
                original: 'ハ',
                start: 6,
                end: 7,
                candidates: <OcrRepairCandidate>[OcrRepairCandidate(text: 'バ')],
              ),
              candidate: OcrRepairCandidate(text: 'バ'),
            ),
          ],
          id: 'repair-2',
        );
        expect(multi, isNotNull);
        expect(multi!.text, '何卒コンパンバ');
        expect(baseline.text, '何卒コンニチハ');
      },
    );
  });
}
