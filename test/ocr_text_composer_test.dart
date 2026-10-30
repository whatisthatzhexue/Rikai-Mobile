import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/ocr/ocr_text_composer.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

OcrBlock _block(String text) =>
    OcrBlock(text: text, left: 0, top: 0, right: 10, bottom: 10);

void main() {
  test('joins native line blocks and normalises whitespace', () {
    final text = composeOcrText([
      _block('  ありがとう  '),
      _block('  '),
      _block('  ありがとう  '),
      _block('ございます'),
    ]);

    // Repeated lines (lyrics, dialogue, table cells) are content, not noise.
    expect(text, 'ありがとう\nありがとう\nございます');
  });

  test('empty input produces empty text', () {
    expect(composeOcrText(const []), '');
    expect(composeOcrText([_block('  ')]), '');
  });

  test('removes OCR spaces inside Japanese runs and around punctuation', () {
    final text = composeOcrText([
      _block('東京 で 食べ た'),
      _block('「 ありがとう 」 と 言った'),
      _block('Hello world 東京'),
    ]);

    expect(text, '東京で食べた\n「ありがとう」と言った\nHello world 東京');
  });
}
