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

  test('rejects malformed or nested tags', () {
    expect(isWellFormedRichText(_tagged), isTrue);
    expect(isWellFormedRichText('[BOLD]未闭合'), isFalse);
    expect(
      isWellFormedRichText('[BOLD][UNDERLINE]x[/UNDERLINE][/BOLD]'),
      isFalse,
    );
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
