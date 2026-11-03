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
    expect(isWellFormedRichText('[RUBY=漢字]何卒[/RUBY]'), isFalse);
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
      expect(prompt, contains('绝对禁止修改、删除或增加原文中的任何一个字符（包括标点符号、空格、换行）'));
    },
  );

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
