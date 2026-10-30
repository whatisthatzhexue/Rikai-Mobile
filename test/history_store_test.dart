import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rikai_ocr/rikai_ocr.dart';
import 'package:rikai_mobile/core/models/capture_photo.dart';
import 'package:rikai_mobile/features/capture/capture_corpus.dart';
import 'package:rikai_mobile/services/storage/history_store.dart';

void main() {
  test('photo blocks are serialized for the corpus record', () {
    final result = PhotoOcrResult(
      text: 'テスト',
      engine: 'paddle_v5',
      elapsedMs: 10,
      blocks: const [
        OcrBlock(
          text: 'テスト',
          left: 1,
          top: 2,
          right: 3,
          bottom: 4,
          orientation: 'horizontal',
        ),
      ],
    );

    final decoded = jsonDecode(encodePhotoBlocks(result)) as List<dynamic>;
    expect(decoded, hasLength(1));
    final block = decoded.single as Map<String, dynamic>;
    expect(block['text'], 'テスト');
    expect(block['left'], 1);
    expect(block['orientation'], 'horizontal');
  });

  test('corpus images are limited to 2048 px and encoded as JPEG', () {
    final source = img.Image(width: 3000, height: 1000);
    img.fill(source, color: img.ColorRgb8(120, 80, 40));
    final png = Uint8List.fromList(img.encodePng(source));

    final encoded = HistoryStore.compressCorpusImage(png);

    expect(encoded, isNotNull);
    expect(encoded![0], 0xFF);
    expect(encoded[1], 0xD8);
    final decoded = img.decodeJpg(encoded)!;
    expect(decoded.width, 2048);
    expect(decoded.height, 683);
  });

  test('undecodable bytes are rejected without throwing', () {
    expect(
      HistoryStore.compressCorpusImage(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
  });
}
