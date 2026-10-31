import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/models/dictionary_sample.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

void main() {
  test('input envelope round-trips without exposing an image path', () {
    const envelope = AgentInputEnvelope(
      sessionId: 'sess-1',
      mode: AgentMode.strict,
      userText: '请解释这句话',
      context: '漫画页',
      dictionaries: <AgentDictionaryRef>[
        AgentDictionaryRef(id: 'dict_a', title: 'A', order: 0),
      ],
      sources: <AgentSourceInput>[
        AgentSourceInput(
          id: 'src-1',
          kind: AgentSourceKind.imageOcr,
          imageId: 'img-1',
          selectedVariantId: 'var-1',
          variants: <AgentOcrVariant>[
            AgentOcrVariant(
              id: 'var-1',
              engine: 'paddle_v5',
              mode: OcrMode.auto,
              text: '何卒宜しくお願い致します。',
              confidence: 0.93,
              elapsedMs: 1200,
            ),
          ],
        ),
        AgentSourceInput(
          id: 'src-2',
          kind: AgentSourceKind.userText,
          text: '用户文本',
        ),
      ],
    );

    final json = envelope.toJson();
    expect(json['schema'], 'rikai.agent.input.v1');
    expect(json.containsKey('image_path'), isFalse);
    expect(json.toString().contains('/sdcard'), isFalse);

    final restored = AgentInputEnvelope.fromJson(json);
    expect(restored.mode, AgentMode.strict);
    expect(restored.sources.first.imageId, 'img-1');
    expect(restored.sources.first.selectedVariant!.mode, OcrMode.auto);
    expect(restored.sources.last.text, '用户文本');
  });

  test('evidence bundle preserves citation order and plain snippets', () {
    const bundle = AgentEvidenceBundle(
      sources: <AgentSourceEvidence>[
        AgentSourceEvidence(
          id: 'src-1',
          kind: 'image_ocr',
          text: '何卒',
          tokens: <AgentTokenEvidence>[
            AgentTokenEvidence(
              id: 't1',
              surface: '何卒',
              reading: 'なにとぞ',
              start: 0,
              end: 2,
              content: true,
              lookupCandidates: <String>['何卒', 'なにとぞ'],
            ),
          ],
        ),
      ],
      citations: <AgentCitation>[
        AgentCitation(
          id: 'source-1',
          kind: 'mdict',
          dictionaryId: 'dict_a',
          dictionaryTitle: 'A',
          dictionaryOrder: 0,
          entryKey: '何卒',
          headword: '何卒',
          snippet: 'なにとぞ。どうか。',
          toolCallId: 'call_1',
        ),
      ],
      budget: AgentEvidenceBudget(
        sourceChars: 2,
        uniqueTargets: 1,
        citations: 1,
      ),
    );

    final restored = AgentEvidenceBundle.fromJson(bundle.toJson());
    expect(restored.citations.single.dictionaryOrder, 0);
    expect(restored.citations.single.snippet, 'なにとぞ。どうか。');
    expect(restored.sources.single.tokens.single.lookupCandidates, [
      '何卒',
      'なにとぞ',
    ]);
  });

  test('analysis round-trips structured claims and epistemic classes', () {
    const analysis = AgentAnalysis(
      sourceId: 'src-1',
      translation: <AgentTranslation>[
        AgentTranslation(quoteId: 'q1', text: '请多关照。'),
      ],
      segments: <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          literal: '何卒宜しくお願い致します。',
          interpretation: '正式请求',
          epistemic: AgentEpistemic.dictionaryFact,
          wordNotes: <AgentWordNote>[
            AgentWordNote(
              tokenId: 't1',
              surface: '何卒',
              reading: 'なにとぞ',
              sense: '请务必',
              citationIds: <String>['source-1'],
            ),
          ],
          grammarNotes: <AgentGrammarNote>[
            AgentGrammarNote(
              patternId: 'p1',
              explanation: '谦让表达',
              citationIds: <String>['source-1'],
            ),
          ],
        ),
      ],
      interpretations: <AgentInterpretation>[
        AgentInterpretation(
          id: 'i1',
          label: 'A',
          meaning: '正式请求',
          confidence: 0.8,
          citationIds: <String>['source-1'],
        ),
      ],
    );

    final restored = AgentAnalysis.fromJson(analysis.toJson());
    expect(restored.segments.single.epistemic, AgentEpistemic.dictionaryFact);
    expect(restored.segments.single.wordNotes.single.sense, '请务必');
    expect(restored.translation.single.quoteId, 'q1');
  });

  test('dictionary profile and quote round-trip', () {
    const profile = DictionaryProfile(
      dictionaryId: 'dict_a',
      title: 'A',
      kind: '国語辞典',
      entryStructure: DictionaryEntryStructure(
        headwordFields: <String>['見出し'],
        definitionFields: <String>['語義'],
        hasRuby: true,
      ),
      searchBehavior: DictionarySearchBehavior(
        exactForms: <String>['漢字', 'かな'],
        prefixSuggestions: true,
      ),
      confidence: 0.8,
    );
    expect(
      DictionaryProfile.fromJson(profile.toJson()).entryStructure.hasRuby,
      isTrue,
    );

    const quote = AgentQuoteRef(
      id: 'q1',
      sourceId: 'src-1',
      start: 0,
      end: 2,
      text: '何卒',
      origin: AgentQuoteOrigin.ocr,
    );
    expect(AgentQuoteRef.fromJson(quote.toJson()).text, '何卒');
  });

  test('dictionary sample round-trips plain-text features', () {
    const sample = DictionarySample(
      dictionaryId: 'dict_a',
      metadata: DictionarySampleMetadata(
        title: 'A',
        entryCount: 10,
        hasMdd: true,
      ),
      entries: <DictionarySampleEntry>[
        DictionarySampleEntry(
          matchedKey: '何卒',
          headword: '何卒',
          snippet: 'なにとぞ',
          features: DictionarySampleFeatures(hasRuby: true, tagCount: 3),
        ),
      ],
    );
    final restored = DictionarySample.fromJson(sample.toJson());
    expect(restored.entries.single.features.hasRuby, isTrue);
    expect(restored.entries.single.snippet, 'なにとぞ');
  });

  test('provider base URLs require HTTPS and a host', () {
    expect(agentBaseUrlError('https://api.deepseek.com'), isNull);
    expect(agentBaseUrlError('http://api.deepseek.com'), contains('HTTPS'));
    expect(agentBaseUrlError(''), contains('Base URL'));
    expect(agentBaseUrlError('not a url'), contains('有效'));
    expect(agentBaseUrlError('https://user:pass@example.com'), contains('账号'));
  });

  test('provider presets fill known service addresses', () {
    expect(AgentProviderPreset.deepSeek.label, 'DeepSeek');
    expect(
      AgentProviderPreset.deepSeek.defaultBaseUrl,
      'https://api.deepseek.com/',
    );
    expect(
      AgentProviderPreset.anthropic.defaultBaseUrl,
      'https://api.anthropic.com/',
    );
    expect(AgentProviderPreset.forConfig(null), AgentProviderPreset.deepSeek);

    const anthropic = AgentProviderConfig(
      id: 'a',
      kind: AgentProviderKind.anthropic,
      displayName: 'Claude',
      baseUrl: 'https://api.anthropic.com',
      smallModel: 'small',
      complexModel: 'large',
    );
    expect(
      AgentProviderPreset.forConfig(anthropic),
      AgentProviderPreset.anthropic,
    );

    const custom = AgentProviderConfig(
      id: 'c',
      kind: AgentProviderKind.openAiCompatible,
      displayName: 'Custom',
      baseUrl: 'https://example.com/v1',
      smallModel: 'small',
      complexModel: 'large',
    );
    expect(AgentProviderPreset.forConfig(custom), AgentProviderPreset.custom);
  });
}
