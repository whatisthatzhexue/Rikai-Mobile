import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/utils/rich_text_tags.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_mobile/services/agent/rich_text_post_processor.dart';

const _plain = '何卒宜しくお願いします。';
const _tagged =
    '[RUBY=なにとぞ]何卒[/RUBY][BOLD]宜しく[/BOLD]'
    '[UNDERLINE]お願いします[/UNDERLINE]。';

void main() {
  group('batched sections degrade independently', () {
    test('accepts each valid section in one batched response', () async {
      final provider = FakeProvider(
        responseText: '''
<<<RIKAI_SECTION original>>>
[RUBY=なにとぞ]何卒[/RUBY]宜しく
<<<RIKAI_END original>>>
<<<RIKAI_SECTION segment-0>>>
[BOLD]何卒[/BOLD]
<<<RIKAI_END segment-0>>>
''',
      );
      final results = await RichTextPostProcessor(llm: provider, model: 'small')
          .processSections(
            <String>['original', 'segment-0'],
            <String>['何卒宜しく', '何卒'],
          );
      expect(results, hasLength(2));
      expect(results[0].taggedText, contains('[RUBY=なにとぞ]'));
      expect(results[1].taggedText, contains('[BOLD]何卒[/BOLD]'));
      expect(provider.requests, hasLength(1));
    });

    test('a damaged marker only rejects that section', () async {
      final provider = FakeProvider(
        responseText: '''
<<<RIKAI_SECTION original>>>
[RUBY=なにとぞ]何卒[/RUBY]宜しく
<<<RIKAI_END original>>>
<<<RIKAI_SECTION segment-0
[BOLD]何卒[/BOLD]
<<<RIKAI_END segment-0>>>
<<<RIKAI_SECTION segment-1>>>
[BOLD]宜しく[/BOLD]
<<<RIKAI_END segment-1>>>
''',
      );
      final results = await RichTextPostProcessor(llm: provider, model: 'small')
          .processSections(
            <String>['original', 'segment-0', 'segment-1'],
            <String>['何卒宜しく', '何卒', '宜しく'],
          );
      expect(results[0].accepted, isTrue);
      expect(results[1].accepted, isFalse);
      expect(results[1].rejectionReason, 'batch_marker');
      expect(results[2].accepted, isTrue);
    });

    test('a diff failure only rejects that section', () async {
      final provider = FakeProvider(
        responseText: '''
<<<RIKAI_SECTION original>>>
[RUBY=なにとぞ]何卒[/RUBY]
<<<RIKAI_END original>>>
<<<RIKAI_SECTION segment-0>>>
[BOLD]何卒！[/BOLD]
<<<RIKAI_END segment-0>>>
<<<RIKAI_SECTION segment-1>>>
[BOLD]宜しく[/BOLD]
<<<RIKAI_END segment-1>>>
''',
      );
      final results = await RichTextPostProcessor(llm: provider, model: 'small')
          .processSections(
            <String>['original', 'segment-0', 'segment-1'],
            <String>['何卒', '何卒', '宜しく'],
          );
      expect(results[0].accepted, isTrue);
      expect(results[1].accepted, isFalse);
      expect(results[2].accepted, isTrue);
    });
  });

  test('strips only known tags and keeps every other character', () {
    expect(stripRichTextTags(_tagged), _plain);
    expect(stripRichTextTags('plain text'), 'plain text');
  });

  test('accepts proper nesting but rejects malformed tags', () {
    expect(isWellFormedRichText(_tagged), isTrue);
    expect(isWellFormedRichText('[BOLD]未闭合'), isFalse);
    expect(
      isWellFormedRichText('[BOLD][UNDERLINE]x[/UNDERLINE][/BOLD]'),
      isTrue,
    );
    expect(isWellFormedRichText('[BOLD][RUBY=かんじ]漢字[/RUBY][/BOLD]'), isTrue);
    expect(
      isWellFormedRichText('[UNDERLINE][RUBY=かんじ]漢字[/RUBY][/UNDERLINE]'),
      isTrue,
    );
    expect(
      isWellFormedRichText('[BOLD][UNDERLINE]x[/BOLD][/UNDERLINE]'),
      isFalse,
    );
    expect(isWellFormedRichText('[RUBY=かんじ][BOLD]漢字[/BOLD][/RUBY]'), isFalse);
    expect(
      isWellFormedRichText('[RUBY=かんじ]漢字[YOMI]（かんじ）[/YOMI][/RUBY]'),
      isFalse,
    );
    expect(isWellFormedRichText('[BOLD][BOLD]x[/BOLD][/BOLD]'), isFalse);
    expect(isWellFormedRichText('[RUBY=漢字]何卒[/RUBY]'), isTrue);
    expect(isWellFormedRichText('[RUBY=nǐ hǎo]你好[/RUBY]'), isTrue);
    expect(isWellFormedRichText('[RUBY=に\nとぞ]何卒[/RUBY]'), isFalse);
  });

  test(
    'accepts tagged output only when the stripped text is identical',
    () async {
      final provider = FakeProvider(responseText: _tagged);
      final result = await RichTextPostProcessor(
        llm: provider,
        model: 'small',
      ).process(_plain);

      expect(result.accepted, isTrue);
      expect(result.taggedText, _tagged);
      final prompt = provider.requests.single.messages
          .map((message) => message.text)
          .join('\n');
      final normalizedPrompt = prompt.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        normalizedPrompt,
        contains(
          'absolutely forbidden to modify, delete or add any character of the '
          'original text',
        ),
      );
      expect(prompt, contains('[YOMI]...[/YOMI]'));
      expect(prompt, contains('If they are identical, do not add RUBY.'));
    },
  );

  test('converts bare YOMI to the bracket display form', () {
    expect(stripYomiTags('何卒[YOMI]なにとぞ[/YOMI]'), 'なにとぞ【何卒】');
    expect(stripYomiTags('何卒[YOMI]（なにとぞ）[/YOMI]'), 'なにとぞ【何卒】');
    expect(stripYomiTags('ます[YOMI]ます[/YOMI]'), 'ます');
    expect(
      richTextToPlain('[RUBY=なにとぞ]何卒[/RUBY][YOMI]なにとぞ[/YOMI]'),
      'なにとぞ【何卒】',
    );
  });

  test('sends the original YOMI text to the formatter', () async {
    const source = '今[YOMI]いま[/YOMI]は';
    final provider = FakeProvider(responseText: source);
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    final promptText = provider.requests.single.messages.last.text;
    expect(promptText, source);
    expect(promptText, isNot(contains('[RUBY=')));
  });

  test('falls back to local YOMI-to-RUBY when the formatter fails', () async {
    final provider = FakeProvider(responseText: 'not a valid tagged response');
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process('今[YOMI]いま[/YOMI]は');

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=いま]今[/RUBY]は');
    expect(result.rejectionReason, 'local_yomi_fallback');
  });

  test('does not convert a parenthesized Chinese explanation', () async {
    const source = '她（かのじょ）は';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, source);
    expect(result.taggedText, isNot(contains('[RUBY=')));
  });

  test('converts a bracket reading to RUBY locally', () async {
    const source = 'すき【好き】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=すき]好き[/RUBY]');
  });

  test('accepts the reversed bracket order', () async {
    const source = '好き【すき】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=すき]好き[/RUBY]');
  });

  test('does not convert an ambiguous all-kanji bracket', () async {
    const source = '大切【重要】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, source);
  });

  test('falls back to bracket RUBY when the provider fails', () async {
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: 'not a valid tagged response'),
      model: 'small',
    ).process('すき【好き】');

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=すき]好き[/RUBY]');
  });

  test('keeps model BOLD while converting retained YOMI locally', () async {
    const source = '今[YOMI]いま[/YOMI]は大切';
    final provider = FakeProvider(
      responseText: '今[YOMI]いま[/YOMI]は[BOLD]大切[/BOLD]',
    );
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=いま]今[/RUBY]は[BOLD]大切[/BOLD]');
  });

  test('converts retained YOMI to RUBY instead of parentheses', () async {
    final provider = FakeProvider(responseText: '今[YOMI]いま[/YOMI]は');
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process('今[YOMI]いま[/YOMI]は');

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=いま]今[/RUBY]は');
  });

  test('removes RUBY pairs whose reading equals their base', () {
    expect(stripRedundantRubyTags('[RUBY=ます]ます[/RUBY]'), 'ます');
    expect(
      stripRedundantRubyTags('[RUBY=かんじ]漢字[/RUBY]'),
      '[RUBY=かんじ]漢字[/RUBY]',
    );
  });

  test('converts display tags to the bracket copyable form', () {
    expect(
      richTextToPlain('[RUBY=なにとぞ]何卒[/RUBY][BOLD]宜しく[/BOLD]'),
      'なにとぞ【何卒】宜しく',
    );
    expect(richTextToPlain('[RUBY=ます]ます[/RUBY]'), 'ます');
    expect(richTextToPlain('[RUBY=（いま）]今[/RUBY]'), 'いま【今】');
    expect(richTextToPlain('[RUBY=いま]今（いま）[/RUBY]'), 'いま【今】');
    expect(richTextToPlain('[RUBY=いま]今(いま)[/RUBY]'), 'いま【今】');
    expect(richTextToPlain('[RUBY=いま]今[/RUBY]（いま）'), 'いま【今】');
    expect(richTextToPlain('[RUBY=いま]今[/RUBY]【いま】'), 'いま【今】');
    expect(richTextToPlain('[RUBY=いま]今[/RUBY]【今】'), 'いま【今】');
    expect(richTextToPlain('[RUBY=すき]好き[/RUBY]'), 'すき【好き】');
    expect(richTextToPlain('ます[YOMI]（ます）[/YOMI]'), 'ます');
  });

  test('keeps one bracket reading when RUBY wraps the annotation', () async {
    const source = 'いま【今】：现在、此刻';
    for (final candidate in <String>[
      '[RUBY=いま]今【いま】[/RUBY]：现在、此刻',
      '[RUBY=いま]今[/RUBY]【いま】：现在、此刻',
    ]) {
      final result = await RichTextPostProcessor(
        llm: FakeProvider(responseText: candidate),
        model: 'small',
      ).process(source);

      expect(result.accepted, isTrue);
      expect(richTextToPlain(result.taggedText!), source);
    }
  });

  test('moves a reading outside a closed BOLD back inside as RUBY', () async {
    const source = '今[YOMI]いま[/YOMI]は、たいせつ【大切】';
    const candidate = '今[YOMI]いま[/YOMI]は、[BOLD]たいせつ[/BOLD]【大切】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: candidate),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(
      result.taggedText,
      '[RUBY=いま]今[/RUBY]は、[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]',
    );
    expect(result.taggedText, isNot(contains('【大切】')));
  });

  test('wraps a reading inside BOLD as RUBY', () async {
    const source = 'たいせつ【大切】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[BOLD]たいせつ【大切】[/BOLD]'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]');
  });

  test('drops a duplicate reading after a closed BOLD RUBY', () async {
    const source = 'たいせつ【大切】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(
        responseText: '[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]たいせつ【大切】',
      ),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]');
    expect(result.taggedText, isNot(contains('【大切】')));
  });

  test(
    'moves a reading outside a closed UNDERLINE back inside as RUBY',
    () async {
      const source = 'たいせつ【大切】';
      final result = await RichTextPostProcessor(
        llm: FakeProvider(responseText: '[UNDERLINE]たいせつ[/UNDERLINE]【大切】'),
        model: 'small',
      ).process(source);

      expect(result.accepted, isTrue);
      expect(result.taggedText, '[UNDERLINE][RUBY=たいせつ]大切[/RUBY][/UNDERLINE]');
    },
  );

  test('keeps an ambiguous all-kanji bracket outside BOLD', () async {
    const source = '大切【重要】';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[BOLD]大切[/BOLD]【重要】'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[BOLD]大切[/BOLD]【重要】');
  });

  test('local display converts YOMI and tag-boundary readings to RUBY', () {
    expect(localReadingsToRuby('今[YOMI]いま[/YOMI]は'), '[RUBY=いま]今[/RUBY]は');
    expect(
      bracketReadingsToRuby('[BOLD]たいせつ[/BOLD]【大切】'),
      '[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]',
    );
    expect(
      bracketReadingsToRuby('[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]たいせつ【大切】'),
      '[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]',
    );
    expect(bracketReadingsToRuby('すき【好き】'), '[RUBY=すき]好き[/RUBY]');
    expect(bracketReadingsToRuby('好き【すき】'), '[RUBY=すき]好き[/RUBY]');
    expect(bracketReadingsToRuby('她（かのじょ）'), '她（かのじょ）');
  });

  test(
    'batch mode converts bracket readings inside and outside BOLD',
    () async {
      final provider = FakeProvider(
        responseText: '''
<<<RIKAI_SECTION original>>>
たいせつ【大切】
<<<RIKAI_END original>>>
<<<RIKAI_SECTION segment-0>>>
[BOLD]たいせつ[/BOLD]【大切】
<<<RIKAI_END segment-0>>>
''',
      );
      final results = await RichTextPostProcessor(llm: provider, model: 'small')
          .processSections(
            <String>['original', 'segment-0'],
            <String>['たいせつ【大切】', '[BOLD]たいせつ[/BOLD]【大切】'],
          );

      expect(results[0].taggedText, '[RUBY=たいせつ]大切[/RUBY]');
      expect(results[1].taggedText, '[BOLD][RUBY=たいせつ]大切[/RUBY][/BOLD]');
    },
  );

  test('allows a whole YOMI block to be replaced by RUBY', () async {
    const source = 'ます[YOMI]（ます）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[RUBY=ます]ます[/RUBY]'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    // The formatter's RUBY was redundant (reading == base), so it is removed.
    expect(result.taggedText, 'ます');
  });

  test('accepts a non-redundant RUBY replacement', () async {
    const source = '漢字[YOMI]（かんじ）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[RUBY=かんじ]漢字[/RUBY]'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=かんじ]漢字[/RUBY]');
  });

  test('accepts pinyin as a RUBY pronunciation', () async {
    const source = '你好[YOMI]（nǐ hǎo）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[RUBY=nǐ hǎo]你好[/RUBY]'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=nǐ hǎo]你好[/RUBY]');
  });

  test('accepts source that already contains display tags', () async {
    const source = '请多关照：[RUBY=なにとぞ]何卒[/RUBY]。';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, source);
  });

  test('cleans punctuation from a RUBY reading before using it', () async {
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[RUBY=（いま）、]今[/RUBY]'),
      model: 'small',
    ).process('今');

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=いま]今[/RUBY]');
  });

  test('ignores punctuation when comparing retained YOMI contents', () {
    expect(
      allowsYomiDeletion('A[YOMI]（a）[/YOMI]B', 'A[YOMI]a[/YOMI]B'),
      isTrue,
    );
  });

  test(
    'detailed formatter permits BOLD/UNDERLINE without a vague escape',
    () async {
      final provider = FakeProvider(responseText: '[RUBY=いま]今[/RUBY]');
      final result = await RichTextPostProcessor(
        llm: provider,
        model: 'small',
      ).process('今', detailed: true);

      expect(result.accepted, isTrue);
      final prompt = provider.requests.single.messages
          .map((message) => message.text)
          .join('\n');
      final normalizedPrompt = prompt.replaceAll(RegExp(r'\s+'), ' ');
      expect(prompt, contains('[BOLD]'));
      expect(prompt, contains('[UNDERLINE]'));
      expect(prompt, isNot(contains('If you are uncertain')));
      expect(
        normalizedPrompt,
        isNot(contains('do not return the whole text unchanged')),
      );
      expect(normalizedPrompt, isNot(contains('entire input unchanged')));
      expect(
        normalizedPrompt,
        isNot(contains('Keep each pair exactly as supplied')),
      );
      expect(
        normalizedPrompt,
        isNot(contains('Convert those YOMI blocks to RUBY')),
      );
      expect(
        normalizedPrompt,
        contains('Reading annotations use corner brackets'),
      );
      expect(
        normalizedPrompt,
        contains('Parentheses `（...）` are ordinary Chinese explanations'),
      );
      expect(normalizedPrompt, contains('put the RUBY inside that span'));
    },
  );

  test('converts a retained YOMI block to RUBY', () async {
    const source = '漢字[YOMI]（かんじ）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '[RUBY=かんじ]漢字[/RUBY]');
  });

  test('falls back to the source when a YOMI block is rewritten', () async {
    const source = 'ます[YOMI]（ます）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: 'ます[YOMI]（マス）[/YOMI]'),
      model: 'small',
    ).process(source);

    // The malformed model output is discarded; the source's own YOMI is
    // converted locally. Here reading == base, so the YOMI disappears.
    expect(result.accepted, isTrue);
    expect(result.taggedText, 'ます');
    expect(result.rejectionReason, 'local_yomi_fallback');
  });

  test('falls back locally when a YOMI block moves', () async {
    const source = 'A[YOMI]（a）[/YOMI]B';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[YOMI]（a）[/YOMI]AB'),
      model: 'small',
    ).process(source);

    // The moved model annotation is rejected; the source's own YOMI is still
    // converted locally so the reading is not lost.
    expect(result.accepted, isTrue);
    expect(result.rejectionReason, 'local_yomi_fallback');
    expect(result.taggedText, '[RUBY=a]A[/RUBY]B');
  });

  test('falls back to the source when a YOMI block is malformed', () async {
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: 'ます[YOMI]（ます）'),
      model: 'small',
    ).process('ます[YOMI]（ます）[/YOMI]');

    expect(result.accepted, isTrue);
    expect(result.taggedText, 'ます');
    expect(result.rejectionReason, 'local_yomi_fallback');
  });

  test('accepts RUBY nested inside BOLD and UNDERLINE', () async {
    const candidate = '[BOLD][UNDERLINE][RUBY=かんじ]漢字[/RUBY][/UNDERLINE][/BOLD]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: candidate),
      model: 'small',
    ).process('漢字');

    expect(result.accepted, isTrue);
    expect(result.taggedText, candidate);
  });

  test('rejects output that changes the original text', () async {
    final provider = FakeProvider(responseText: '[BOLD]何卒様[/BOLD]宜しくお願いします。');
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process(_plain);

    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'text_changed');
    expect(result.taggedText, isNull);
  });

  test(
    'repairs an unclosed style tag instead of discarding the section',
    () async {
      final provider = FakeProvider(responseText: '[BOLD]$_plain');
      final result = await RichTextPostProcessor(
        llm: provider,
        model: 'small',
      ).process(_plain);

      expect(result.accepted, isTrue);
      expect(result.rejectionReason, 'tags_repaired');
      expect(result.taggedText, _plain);
    },
  );

  test(
    'keeps valid style tags when an orphan closing tag is present',
    () async {
      final provider = FakeProvider(
        responseText: '[BOLD]何卒[/BOLD][/UNDERLINE]宜しくお願いします。',
      );
      final result = await RichTextPostProcessor(
        llm: provider,
        model: 'small',
      ).process(_plain);

      expect(result.accepted, isTrue);
      expect(result.rejectionReason, 'tags_repaired');
      expect(result.taggedText, contains('[BOLD]何卒[/BOLD]'));
      expect(stripRichTextTags(result.taggedText!), _plain);
    },
  );

  test('malformed RUBY still falls back instead of guessing', () async {
    final provider = FakeProvider(responseText: '[RUBY=なにとぞ]何卒宜しくお願いします。');
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process(_plain);

    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'malformed_tags');
  });

  test('formatter prompt follows the selected explanation language', () async {
    final provider = FakeProvider(responseText: _tagged);
    await RichTextPostProcessor(
      llm: provider,
      model: 'small',
      responseLanguage: AgentResponseLanguage.english,
    ).process(_plain, detailed: true);

    final prompt = provider.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(prompt, contains('English explanations'));
    expect(prompt, isNot(contains('Chinese explanations')));
  });
}
