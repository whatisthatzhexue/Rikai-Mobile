import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/ocr_model.dart';

void main() {
  test('parses the checked-in OCR manifest', () {
    final raw = File('assets/models/manifest.json').readAsStringSync();
    final manifest = OcrModelManifest.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );

    expect(manifest.sets['paddle_v5'], isNotNull);
    expect(manifest.sets['paddle_v5']!.files, hasLength(3));
    expect(manifest.sets['paddle_v5']!.totalSize, 21509645);
    expect(
      manifest.sets['paddle_v5']!.files.first.urls.first,
      contains('hf-mirror'),
    );
    expect(manifest.sets['manga_ocr']!.requiresAcceptance, isTrue);
    expect(manifest.sets['orientation']!.files, hasLength(2));
  });

  test('rejects an empty or malformed set', () {
    expect(
      () => OcrModelManifest.fromJson(const {'sets': {}}),
      throwsFormatException,
    );
    expect(
      () => OcrModelSet.fromJson('bad', const {'files': []}),
      throwsFormatException,
    );
    expect(
      () => OcrModelFile.fromJson(const {
        'name': 'x.onnx',
        'urls': <String>[],
        'size': 1,
      }),
      throwsFormatException,
    );
  });
}
