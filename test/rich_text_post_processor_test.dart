import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/utils/rich_text_tags.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_mobile/services/agent/rich_text_post_processor.dart';

const _plain = '何卒宜しくお願いします。';
const _tagged =
    '[RUBY=なにとぞ]何卒[/RUBY][BOLD]宜しく[/BOLD]'
    '[UNDERLINE]お願いします[/UNDERLINE]。';

void main() {
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

  test('removes RUBY pairs whose reading equals their base', () {
    expect(stripRedundantRubyTags('[RUBY=ます]ます[/RUBY]'), 'ます');
    expect(
      stripRedundantRubyTags('[RUBY=かんじ]漢字[/RUBY]'),
      '[RUBY=かんじ]漢字[/RUBY]',
    );
  });

  test('converts display tags to copyable plain text', () {
    expect(
      richTextToPlain('[RUBY=なにとぞ]何卒[/RUBY][BOLD]宜しく[/BOLD]'),
      '何卒（なにとぞ）宜しく',
    );
    expect(richTextToPlain('[RUBY=ます]ます[/RUBY]'), 'ます');
    expect(richTextToPlain('[RUBY=（いま）]今[/RUBY]'), '今（いま）');
    expect(richTextToPlain('[RUBY=いま]今（いま）[/RUBY]'), '今（いま）');
    expect(richTextToPlain('[RUBY=いま]今(いま)[/RUBY]'), '今（いま）');
    expect(richTextToPlain('[RUBY=いま]今[/RUBY]（いま）'), '今（いま）');
    expect(richTextToPlain('ます[YOMI]（ます）[/YOMI]'), 'ます（ます）');
  });

  test(
    'keeps one parenthetical reading when RUBY wraps the annotation',
    () async {
      const source = '今（いま）：现在、此刻';
      for (final candidate in <String>[
        '[RUBY=いま]今（いま）[/RUBY]：现在、此刻',
        '[RUBY=いま]今[/RUBY]（いま）：现在、此刻',
      ]) {
        final result = await RichTextPostProcessor(
          llm: FakeProvider(responseText: candidate),
          model: 'small',
        ).process(source);

        expect(result.accepted, isTrue);
        expect(richTextToPlain(result.taggedText!), source);
      }
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
        contains('do not return the whole text unchanged'),
      );
    },
  );

  test('keeps the parenthetical reading when YOMI is retained', () async {
    const source = '漢字[YOMI]（かんじ）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: source),
      model: 'small',
    ).process(source);

    expect(result.accepted, isTrue);
    expect(result.taggedText, '漢字（かんじ）');
  });

  test('rejects a rewritten YOMI block', () async {
    const source = 'ます[YOMI]（ます）[/YOMI]';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: 'ます[YOMI]（マス）[/YOMI]'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'yomi_changed');
  });

  test('rejects a moved YOMI block', () async {
    const source = 'A[YOMI]（a）[/YOMI]B';
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: '[YOMI]（a）[/YOMI]AB'),
      model: 'small',
    ).process(source);

    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'yomi_changed');
  });

  test('rejects a malformed YOMI block', () async {
    final result = await RichTextPostProcessor(
      llm: FakeProvider(responseText: 'ます[YOMI]（ます）'),
      model: 'small',
    ).process('ます[YOMI]（ます）[/YOMI]');

    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'malformed_yomi');
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

  test('rejects an unclosed formatting tag', () async {
    final provider = FakeProvider(responseText: '[BOLD]何卒宜しくお願いします。');
    final result = await RichTextPostProcessor(
      llm: provider,
      model: 'small',
    ).process(_plain);

    expect(result.accepted, isFalse);
    expect(result.rejectionReason, 'malformed_tags');
  });
}
