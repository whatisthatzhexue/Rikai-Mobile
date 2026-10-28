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

    expect(text, 'ありがとう\nございます');
  });

  test('empty input produces empty text', () {
    expect(composeOcrText(const []), '');
    expect(composeOcrText([_block('  ')]), '');
  });
}
